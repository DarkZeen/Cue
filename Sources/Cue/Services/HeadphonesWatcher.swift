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

    nonisolated enum Kind: Equatable, Sendable {
        case airPods
        case airPodsPro
        case airPodsMax
        case beats
        case headphones

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
            case .headphones: "headphones"
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
    private var clearTask: Task<Void, Never>?
    private let logger = Diagnostics.logger("headphones")

    func start() {
        // Whatever is playing at launch is not an arrival.
        lastDevice = Self.defaultOutputDevice() ?? 0

        var address = Self.defaultOutputAddress
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main
        ) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.outputChanged() }
        }
        if status != noErr {
            logger.error("Could not watch the default output device: \(status, privacy: .public)")
        }
    }

    private func outputChanged() {
        guard let device = Self.defaultOutputDevice(), device != lastDevice else { return }
        lastDevice = device

        guard isEnabled,
              Self.isBluetooth(device),
              let name = Self.name(of: device)
        else { return }

        let arrival = Arrival(id: UUID(), name: name, kind: Kind(name: name), battery: nil)
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
                let battery = await Self.battery(named: name)
                guard let self, self.arrival?.id == arrival.id else { return }
                if let battery {
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
    private static func battery(named name: String) async -> Battery? {
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
        return battery(fromReport: data, deviceName: name)
    }

    /// The levels for `deviceName` in a `system_profiler -json
    /// SPBluetoothDataType` report, or `nil` when it lists none.
    nonisolated static func battery(fromReport data: Data, deviceName: String) -> Battery? {
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
                    return battery.shown == nil && battery.caseLevel == nil ? nil : battery
                }
            }
        }
        return nil
    }

    #if DEBUG
    /// For render tests: an arrival without any headphones.
    static func previewArrival(_ kind: Kind, battery: Battery?) -> Arrival {
        Arrival(id: UUID(), name: "AirPods", kind: kind, battery: battery)
    }
    #endif
}
