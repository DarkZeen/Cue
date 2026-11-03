import CoreAudio
import Foundation
import Observation
import OSLog

/// Notices headphones arriving: AirPods connecting, or moving over to this
/// Mac from a phone — which, to the Mac, are the same thing: the system's
/// sound output switches to a Bluetooth device.
///
/// Core Audio says when the default output device changes, and asks for no
/// permission to say it. That is the whole trigger; nothing polls. The
/// battery comes from the system's own Bluetooth report, which is where
/// macOS keeps the AirPods' left, right and case levels — there is no public
/// API for them — so it is fetched once per arrival, off the main actor, and
/// arrives a moment after the headphones do.
///
/// An arrival lasts a few seconds, then clears: this is the notch saying
/// "your AirPods are here", not a battery indicator that stays.
@MainActor
@Observable
final class HeadphonesWatcher {
    struct Arrival: Equatable, Identifiable {
        let id: UUID
        var name: String
        var kind: Kind
        var battery: Battery?
    }

    nonisolated enum Kind: String, Equatable, Sendable {
        case airPods
        case airPodsPro
        case airPodsMax
        case beats
        case sonyXM5
        case headphones

        /// What the system's Bluetooth report says it is, when the name does
        /// not: headphones named by their owner ("Artemidius") still report
        /// their maker and model.
        init(name: String, vendorID: String?, productID: String?) {
            switch (vendorID?.lowercased(), productID?.lowercased()) {
            case ("0x054c", "0x0df0"): self = .sonyXM5
            default: self.init(name: name)
            }
        }

        /// What the device's name says it is. AirPods are named by their
        /// owner but keep the model in the name — "Alan's AirPods Pro".
        init(name: String) {
            let lower = name.lowercased()
            if lower.contains("airpods max") { self = .airPodsMax }
            else if lower.contains("airpods pro") { self = .airPodsPro }
            else if lower.contains("airpods") { self = .airPods }
            else if lower.contains("beats") { self = .beats }
            else { self = .headphones }
        }

        var symbol: String {
            switch self {
            case .airPods: "airpods"
            case .airPodsPro: "airpodspro"
            case .airPodsMax: "airpodsmax"
            case .beats: "beats.headphones"
            case .sonyXM5, .headphones: "headphones"
            }
        }
    }

    /// Percentages, as the system reports them. AirPods have a left, a right
    /// and a case; over-ear headphones have one.
    nonisolated struct Battery: Equatable, Sendable {
        var left: Int?
        var right: Int?
        var single: Int?
        var caseLevel: Int?

        /// What the ring shows: the emptier ear, because that is the one that
        /// runs out first.
        var shown: Int? {
            [left, right].compactMap { $0 }.min() ?? single
        }

        var summary: String {
            var parts: [String] = []
            if let left { parts.append("Left \(left)%") }
            if let right { parts.append("Right \(right)%") }
            if let single { parts.append("\(single)%") }
            if let caseLevel { parts.append("Case \(caseLevel)%") }
            return parts.joined(separator: " · ")
        }
    }

    /// The headphones that just arrived, for a few seconds; otherwise `nil`.
    private(set) var arrival: Arrival?

    /// Off in Settings, nothing is announced.
    var isEnabled = true {
        didSet { if !isEnabled { clear() } }
    }

    /// How long the notch shows them.
    static let showFor: Duration = .seconds(4)

    private var lastDevice: AudioObjectID = 0
    /// The devices the system had at the last look, so ones that reappear —
    /// AirPods coming back from a phone — can be told apart.
    private var knownDevices: Set<AudioObjectID> = []
    /// When each set of headphones was last announced, by name, so the two
    /// signals for one arrival announce it once.
    private var lastAnnounced: [String: ContinuousClock.Instant] = [:]
    private var clearTask: Task<Void, Never>?
    private var handover = HandoverDetector()
    private var watchedForRunning: Set<AudioObjectID> = []
    private let clock = ContinuousClock()
    private let logger = Diagnostics.logger("headphones")

    /// Two signals, because an arrival is not always a change of output.
    ///
    /// AirPods that leave for a phone can stay the Mac's chosen output while
    /// they are away, so when they come back the output has not "changed" —
    /// but they had dropped out of the system's device list, and they come
    /// back into it. So: the output switching to headphones, or headphones
    /// reappearing and being the output. Whichever comes first announces it.
    func start() {
        // Whatever is playing at launch is not an arrival.
        lastDevice = Self.defaultOutputDevice() ?? 0
        knownDevices = Set(Self.allDevices())

        listen(to: Self.defaultOutputAddress) { $0.outputChanged() }
        listen(to: Self.devicesAddress) { $0.devicesChanged() }
        listen(to: Self.systemOutputAddress) { $0.systemOutputReasserted() }
        watchRunning(knownDevices)
    }

    // MARK: - Handover from another device

    /// Follows whether each device is playing, for `HandoverDetector`.
    private func watchRunning(_ devices: some Sequence<AudioObjectID>) {
        for device in devices where !watchedForRunning.contains(device) {
            watchedForRunning.insert(device)
            handover.running(device, Self.isRunning(device), at: clock.now)

            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(device, &address, DispatchQueue.main) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.handover.running(device, Self.isRunning(device), at: self.clock.now)
                }
            }
        }
    }

    /// macOS says the system output again, unchanged — which is what a
    /// handover from a phone looks like from here. Whether it was them
    /// arriving or leaving is settled a moment later by whether they play.
    private func systemOutputReasserted() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, let output = Self.defaultOutputDevice() else { return }
            self.handover.running(output, Self.isRunning(output), at: self.clock.now)
            if self.handover.arrived(output, at: self.clock.now) {
                self.announce(output)
            }
        }
    }

    private func listen(
        to address: AudioObjectPropertyAddress,
        _ handler: @escaping @MainActor (HeadphonesWatcher) -> Void
    ) {
        var address = address
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main
        ) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
            }
        }
        if status != noErr {
            logger.error("Could not watch audio devices: \(status, privacy: .public)")
        }
    }

    private func outputChanged() {
        guard let device = Self.defaultOutputDevice(), device != lastDevice else { return }
        lastDevice = device
        announce(device)
    }

    private func devicesChanged() {
        let now = Set(Self.allDevices())
        let returned = now.subtracting(knownDevices)
        knownDevices = now
        watchRunning(returned)
        guard !returned.isEmpty else { return }

        // The output is re-chosen a beat after a device appears.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, let output = Self.defaultOutputDevice(), returned.contains(output) else { return }
            self.lastDevice = output
            self.announce(output)
        }
    }

    private func announce(_ device: AudioObjectID) {
        guard isEnabled,
              Self.isBluetooth(device),
              let name = Self.name(of: device)
        else { return }

        let clock = ContinuousClock()
        if let last = lastAnnounced[name], clock.now - last < .seconds(5) { return }
        lastAnnounced[name] = clock.now

        // A kind learned from an earlier report, so headphones named by their
        // owner show as what they are from the first frame.
        let known = Self.rememberedKind(for: name)
        let arrival = Arrival(id: UUID(), name: name, kind: known ?? Kind(name: name), battery: nil)
        logger.notice("Headphones arrived: \(arrival.kind.symbol, privacy: .public).")
        self.arrival = arrival

        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: Self.showFor)
            guard !Task.isCancelled else { return }
            self?.clear()
        }

        Task { [weak self] in
            // The report can lag the connection by a second or two; one
            // more look if the first comes back without levels.
            for wait in [Duration.zero, .milliseconds(1500)] {
                try? await Task.sleep(for: wait)
                let report = await Self.report(named: name)
                guard let self, self.arrival?.id == arrival.id else { return }
                if let report {
                    let kind = Kind(name: name, vendorID: report.vendorID, productID: report.productID)
                    if kind != self.arrival?.kind { self.arrival?.kind = kind }
                    Self.remember(kind, for: name)
                }
                if let battery = report?.battery {
                    self.arrival?.battery = battery
                    return
                }
            }
        }
    }

    private func clear() {
        clearTask?.cancel()
        clearTask = nil
        arrival = nil
    }

    // MARK: - Core Audio

    private static var defaultOutputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var devicesAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var systemOutputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func isRunning(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr && running != 0
    }

    private static func allDevices() -> [AudioObjectID] {
        var address = devicesAddress
        var size = UInt32(0)
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var address = defaultOutputAddress
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return status == noErr && device != 0 ? device : nil
    }

    private static func isBluetooth(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else {
            return false
        }
        return transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func name(of device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr,
              let name
        else { return nil }
        return name.takeRetainedValue() as String
    }

    // MARK: - Battery

    /// Asks the system's Bluetooth report for this device's levels.
    @concurrent
    private static func report(named name: String) async -> DeviceReport? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["-json", "SPBluetoothDataType"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return report(fromReport: data, deviceName: name)
    }

    /// The levels for `deviceName` in a `system_profiler -json
    /// SPBluetoothDataType` report, or `nil` when it lists none.
    nonisolated static func battery(fromReport data: Data, deviceName: String) -> Battery? {
        report(fromReport: data, deviceName: deviceName)?.battery
    }

    /// One device's entry in the report: its levels, and who made it.
    nonisolated struct DeviceReport: Equatable, Sendable {
        var battery: Battery?
        var vendorID: String?
        var productID: String?
    }

    nonisolated static func report(fromReport data: Data, deviceName: String) -> DeviceReport? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return nil }

        func percent(_ value: Any?) -> Int? {
            guard let text = value as? String else { return nil }
            return Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
        }

        for controller in controllers {
            for list in ["device_connected", "device_not_connected"] {
                guard let devices = controller[list] as? [[String: Any]] else { continue }
                for entry in devices {
                    guard let info = entry[deviceName] as? [String: Any] else { continue }
                    let battery = Battery(
                        left: percent(info["device_batteryLevelLeft"]),
                        right: percent(info["device_batteryLevelRight"]),
                        single: percent(info["device_batteryLevelMain"]),
                        caseLevel: percent(info["device_batteryLevelCase"])
                    )
                    return DeviceReport(
                        battery: battery.shown == nil && battery.caseLevel == nil ? nil : battery,
                        vendorID: info["device_vendorID"] as? String,
                        productID: info["device_productID"] as? String
                    )
                }
            }
        }
        return nil
    }

    // MARK: - Remembered kinds

    private static let kindsKey = "headphones.kinds"

    private static func rememberedKind(for name: String) -> Kind? {
        (UserDefaults.standard.dictionary(forKey: kindsKey)?[name] as? String).flatMap(Kind.init(rawValue:))
    }

    private static func remember(_ kind: Kind, for name: String) {
        var kinds = UserDefaults.standard.dictionary(forKey: kindsKey) ?? [:]
        guard kinds[name] as? String != kind.rawValue else { return }
        kinds[name] = kind.rawValue
        UserDefaults.standard.set(kinds, forKey: kindsKey)
    }

    #if DEBUG
    /// For render tests: an arrival without any headphones.
    static func previewArrival(_ kind: Kind, battery: Battery?) -> Arrival {
        Arrival(id: UUID(), name: "AirPods", kind: kind, battery: battery)
    }
    #endif
}

/// Tells headphones coming back from a phone apart from everything else.
///
/// AirPods stay connected to every Apple device they know; only the right to
/// play moves. So when they come back from an iPhone the Mac's output does not
/// change and they never leave its device list — what does happen, recorded
/// during a real handover, is that macOS announces the system output again,
/// unchanged, and the AirPods, silent while they were away, start playing.
/// Leaving also re-announces the output, but while the audio is still
/// flowing; and ordinary playback starts after silence without any
/// announcement. So an arrival is both together: the output re-announced,
/// and the headphones starting to play after a real silence, a moment before.
struct HandoverDetector {
    /// How long they must have been quiet for a start to count as coming back.
    static let silence: Duration = .seconds(3)
    /// How close the start and the announcement have to be.
    static let window: Duration = .milliseconds(2500)

    private var quietSince: [AudioObjectID: ContinuousClock.Instant] = [:]
    private var startedAfterSilence: [AudioObjectID: ContinuousClock.Instant] = [:]

    mutating func running(_ device: AudioObjectID, _ running: Bool, at now: ContinuousClock.Instant) {
        if running {
            if let since = quietSince[device], now - since >= Self.silence {
                startedAfterSilence[device] = now
            }
            quietSince[device] = nil
        } else if quietSince[device] == nil {
            quietSince[device] = now
        }
    }

    /// Asked a moment after the output is re-announced. Answers once.
    mutating func arrived(_ device: AudioObjectID, at now: ContinuousClock.Instant) -> Bool {
        guard quietSince[device] == nil,
              let started = startedAfterSilence[device],
              now - started <= Self.window
        else { return false }
        startedAfterSilence[device] = nil
        return true
    }
}

