import Accelerate
import AudioToolbox
import CoreAudio
import Foundation
import os

/// Reads the music Cue is playing, straight from Core Audio.
///
/// Three attempts to do this inside the web view failed, and the last one
/// failed for a reason that has no way around it: `createMediaElementSource`
/// returns silence for YouTube Music's media in WebKit, *and* takes over the
/// element's output on the way, so the price of asking is the music stopping.
///
/// A process tap asks the operating system instead. macOS 14.4 added them —
/// `AudioHardwareCreateProcessTap`, an aggregate device wrapped around it, and
/// an IO callback that receives exactly what the tapped processes are sending
/// to the speakers. Nothing is intercepted: the tap is a copy, the audio keeps
/// going where it was already going, and there is no way for this to make the
/// music quieter or stop it.
///
/// It costs one permission, which is the honest trade and the reason this is a
/// setting rather than the default.
@Observable
final class AudioTap {
    /// How loud, 0 to 1, already shaped by an envelope.
    private(set) var level: Double = 0
    /// The spectrum, low to high, nine bands.
    private(set) var bands: [Double] = []

    /// Whether audio is actually arriving. False while stopped, and false when
    /// permission was refused — the two look identical from the outside, which
    /// is why the reason is logged rather than guessed at.
    private(set) var isReading = false

    /// What is currently being listened to, so a second call can tell whether
    /// anything has actually changed.
    private var tapped: [AudioObjectID] = []
    private var hasHeardAnything = false

    private var tap: AudioObjectID = .zero
    private var aggregate: AudioObjectID = .zero
    private var ioProc: AudioDeviceIOProcID?
    private var pump: Task<Void, Never>?

    private let analyser = SpectrumAnalyser()
    private let logger = Diagnostics.logger("audio-tap")

    // No `deinit` teardown on purpose. This object lives as long as the app
    // does, and a `deinit` that hops to the main actor to tear down Core Audio
    // is a crash waiting for the one release that happens on another thread.
    // The audio server discards a client's taps and aggregate devices when the
    // process goes, which is the only time this would ever be deallocated.

    // MARK: - Running

    /// Starts, or restarts if what Cue is playing through has changed.
    ///
    /// Called every time playback starts rather than once at launch, because a
    /// tap can only be pointed at a process Core Audio already knows about —
    /// and WebKit's GPU process appears in that list when it first makes a
    /// sound, not when the app launches. Asking again is cheap; the work only
    /// happens when the answer is different from last time.
    func ensureRunning() {
        let targets = Self.ownAudioProcesses()
        guard !targets.isEmpty else { return }
        guard targets != tapped else { return }

        stop()
        start(tapping: targets)
    }

    private func start(tapping targets: [AudioObjectID]) {
        guard aggregate == .zero else { return }

        guard let tap = createTap(for: targets) else { return }
        self.tap = tap

        guard let aggregate = createAggregate(around: tap) else {
            AudioHardwareDestroyProcessTap(tap)
            self.tap = .zero
            return
        }
        self.aggregate = aggregate

        guard let format = Self.property(tap, kAudioTapPropertyFormat, AudioStreamBasicDescription.self) else {
            logger.error("The tap would not say what format it is in.")
            stop()
            return
        }

        analyser.prepare(sampleRate: format.mSampleRate, channels: Int(format.mChannelsPerFrame))
        logger.notice(
            "Tapping \(targets.count, privacy: .public) process(es) at \(format.mSampleRate, privacy: .public)Hz, \(format.mChannelsPerFrame, privacy: .public)ch."
        )

        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(
            &procID,
            aggregate,
            nil,
            Self.callback(into: analyser)
        )

        guard status == noErr, let procID else {
            logger.error("Could not attach to the tap: \(status, privacy: .public).")
            stop()
            return
        }
        ioProc = procID

        // The call that asks for permission. Everything above this line is
        // allowed without it, which is why nothing prompts until Cue is
        // actually about to listen.
        let started = AudioDeviceStart(aggregate, procID)
        guard started == noErr else {
            logger.error("Audio capture refused: \(started, privacy: .public). Permission, most likely.")
            stop()
            return
        }

        tapped = targets
        hasHeardAnything = false
        isReading = true
        startPumping()
    }

    /// Built in a `nonisolated` function on purpose.
    ///
    /// A closure written inside this class inherits the package's main-actor
    /// default, and Core Audio calls it on a real-time thread — so it asserted
    /// its way to a crash the moment audio arrived. Made here, it belongs to
    /// no actor, which is what a callback from the audio system has to be.
    private nonisolated static func callback(into analyser: SpectrumAnalyser) -> AudioDeviceIOBlock {
        { _, input, _, _, _ in analyser.consume(input) }
    }

    func stop() {
        pump?.cancel()
        pump = nil

        if let ioProc, aggregate != .zero {
            AudioDeviceStop(aggregate, ioProc)
            AudioDeviceDestroyIOProcID(aggregate, ioProc)
        }
        ioProc = nil

        if aggregate != .zero { AudioHardwareDestroyAggregateDevice(aggregate) }
        aggregate = .zero

        if tap != .zero { AudioHardwareDestroyProcessTap(tap) }
        tap = .zero

        analyser.reset()
        tapped = []
        isReading = false
        level = 0
        bands = []
    }

    /// Moves readings from the audio thread to the main one, at a rate a
    /// screen can show.
    ///
    /// The IO callback runs on a real-time thread hundreds of times a second
    /// and must not touch SwiftUI, an observable property, or a lock anything
    /// slow holds. So it writes into a small lock-protected snapshot and this
    /// reads it — sixty times a second, which is a display's rate and a long
    /// way below the callback's.
    private func startPumping() {
        pump = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let reading = self.analyser.latest()
                self.level = reading.level
                self.bands = reading.bands

                // Once, when sound first arrives. A tap that starts cleanly and
                // then hears nothing is the failure mode worth naming: it looks
                // exactly like a tap that is working, because the mark keeps
                // moving on invented motion either way.
                if !self.hasHeardAnything, reading.level > 0.05 {
                    self.hasHeardAnything = true
                    self.logger.notice("Hearing the music.")
                }
                // A display's rate while there is something to show, and a
                // quarter second when there is not. Every one of these writes
                // invalidates the views that read it, and doing that sixty
                // times a second through a paused track — or a whole evening
                // with the music stopped — is work nobody asked for.
                try? await Task.sleep(for: reading.level > 0.01
                    ? .milliseconds(16)
                    : .milliseconds(250))
            }
        }
    }

    // MARK: - Building the tap

    private func createTap(for processes: [AudioObjectID]) -> AudioObjectID? {
        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.name = "Cue"
        // Never mute. The whole failure this replaces was a mechanism that
        // took the audio away in order to look at it; a tap does not have to,
        // and saying so explicitly costs one line.
        description.muteBehavior = .unmuted
        // Not offered to other apps as a device. Nothing else has any business
        // seeing a tap Cue made of its own playback.
        description.isPrivate = true

        var tap: AudioObjectID = .zero
        let status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr else {
            logger.error("Could not create the tap: \(status, privacy: .public).")
            return nil
        }
        return tap
    }

    private func createAggregate(around tap: AudioObjectID) -> AudioObjectID? {
        guard let tapUID = Self.property(tap, kAudioTapPropertyUID, CFString.self) as String? else {
            logger.error("The tap has no identifier.")
            return nil
        }

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Cue",
            kAudioAggregateDeviceUIDKey: "com.cue.tap.\(UUID().uuidString)",
            // Nothing in here but the tap. No main sub-device, no sub-device
            // list.
            //
            // The usual recipe names the current output device as the
            // aggregate's main sub-device, to give it a clock. That works and
            // it is wrong here for a reason that only shows up later: the
            // aggregate then holds a reference to whichever device happened to
            // be default when the tap was built, so putting headphones in
            // afterwards leaves Cue's tap wired to the speakers — and an
            // aggregate holding a Bluetooth device it should not have is not
            // something to leave in the path of somebody's music.
            //
            // A tap alone turned out to be enough: measured, with the log
            // saying "Hearing the music" and the output device still running
            // where it was. So the tap is the only member, and there is now no
            // real device in this aggregate for a change of output to
            // invalidate.
            // Private, so it never appears in Sound preferences or in another
            // app's device list.
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapUID
                ]
            ]
        ]

        var aggregate: AudioObjectID = .zero
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregate)
        guard status == noErr else {
            logger.error("Could not build the aggregate device: \(status, privacy: .public).")
            return nil
        }
        return aggregate
    }

    // MARK: - Finding Cue's audio

    /// The audio processes belonging to Cue — which is not Cue's own process.
    ///
    /// `WKWebView` plays its media in a WebKit GPU process, so a tap pointed at
    /// this process taps silence. That process is an XPC service whose parent
    /// is launchd, so it cannot be found by walking children either. What does
    /// identify it is the *responsible* process, which is what macOS uses to
    /// attribute an XPC service's behaviour back to the app that caused it —
    /// measured here as pid 40270 answering 40268, while another browser's
    /// identical WebKit process answered its own app.
    ///
    /// Being exact matters: the fallback would be a global tap, and a mark that
    /// twitches at a notification sound or at a video in another window is
    /// reading the wrong thing.
    static func ownAudioProcesses() -> [AudioObjectID] {
        let ours = getpid()
        let all = list(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)

        return all.filter { object in
            guard let pid = property(object, kAudioProcessPropertyPID, pid_t.self) else { return false }
            return pid == ours || responsibleProcess(for: pid) == ours
        }
    }

    /// The process macOS holds responsible for another one.
    ///
    /// Not in a public header, so it is resolved by name at runtime and the
    /// whole feature degrades to "no processes found" if it ever goes away —
    /// which is a mark that does not move, not a crash and not silence.
    static func responsibleProcess(for pid: pid_t) -> pid_t? {
        typealias Lookup = @convention(c) (pid_t) -> pid_t
        guard let symbol = dlsym(
            UnsafeMutableRawPointer(bitPattern: -2),
            "responsibility_get_pid_responsible_for_pid"
        ) else { return nil }

        let responsible = unsafeBitCast(symbol, to: Lookup.self)(pid)
        return responsible > 0 ? responsible : nil
    }

    // MARK: - Core Audio plumbing

    static func property<T>(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        _ type: T.Type
    ) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, value) == noErr else { return nil }
        return value.pointee
    }

    static func list(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector
    ) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }

        var objects = [AudioObjectID](repeating: .zero, count: count)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }
}
