import AppKit
import CoreAudio
import Foundation

/// Pauses Cue while another app plays sound, and resumes it afterwards.
///
/// Core Audio already keeps a list of every process with audio, and says of
/// each one whether it is sending sound out right now. That is all this reads:
/// no tap, no permission, nothing recorded — a yes or no per app, twice a
/// second, and only while there is music of Cue's to make way with.
///
/// The decisions are `OtherAudioPolicy`'s. This is the part that reads the
/// world and carries them out.
@MainActor
final class OtherAudioWatcher {
    private let player: PlayerService
    private var policy = OtherAudioPolicy()
    private var loop: Task<Void, Never>?

    /// Which apps were sounding at the last reading, so the log can say who
    /// Cue made way for.
    private var lastSounding: [String] = []

    private let logger = Diagnostics.logger("other-audio")

    init(player: PlayerService) {
        self.player = player
    }

    /// Set from the setting.
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? start() : stop()
        }
    }

    private func start() {
        logger.notice("Watching for other apps' sound.")
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func stop() {
        loop?.cancel()
        loop = nil
        lastSounding = []
        if policy.reset() == .resume {
            logger.notice("Stopped watching; resuming the music it had paused.")
            player.resume()
        }
    }

    private func tick() {
        let cuePlaying = player.nowPlaying?.isPlaying == true

        // Nothing of Cue's playing and nothing held: no reading is needed, and
        // none is taken. The next reading that matters is the one where Cue
        // starts, and that one is taken.
        let sounding = (cuePlaying || policy.isEngaged) ? Self.appsPlayingSound() : []
        if !sounding.isEmpty { lastSounding = sounding }

        let now = ProcessInfo.processInfo.systemUptime
        switch policy.update(otherAudio: !sounding.isEmpty, cuePlaying: cuePlaying, at: now) {
        case .pause:
            logger.notice("Paused for \(sounding.joined(separator: ", "), privacy: .public).")
            player.pause()
        case .resume:
            logger.notice("Resumed: \(self.lastSounding.joined(separator: ", "), privacy: .public) went quiet.")
            player.resume()
        case nil:
            break
        }
    }

    /// The apps, other than Cue, sending sound out right now.
    ///
    /// By app rather than by process, because the process that makes the
    /// sound is rarely the app: a browser's video plays in a helper, and
    /// WebKit's in a GPU process belonging to launchd. The *responsible*
    /// process is the app — see `AudioTap.ownAudioProcesses` for how that was
    /// established — and it is also how Cue's own player is told apart from
    /// another WebKit app's.
    ///
    /// Processes that answer to no app are left out: the system sound server,
    /// the charging chime, the speech daemon. A notification is not media, and
    /// none of those are something a person pressed play on.
    static func appsPlayingSound() -> [String] {
        let ours = getpid()
        let objects = AudioTap.list(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)

        let names = objects.compactMap { object -> String? in
            guard AudioTap.property(object, kAudioProcessPropertyIsRunningOutput, UInt32.self) == 1,
                  let pid = AudioTap.property(object, kAudioProcessPropertyPID, pid_t.self)
            else { return nil }

            let owner = AudioTap.responsibleProcess(for: pid) ?? pid
            guard pid != ours, owner != ours else { return nil }

            guard let app = NSRunningApplication(processIdentifier: owner)
                    ?? NSRunningApplication(processIdentifier: pid),
                  app.activationPolicy != .prohibited
            else { return nil }

            return app.localizedName ?? app.bundleIdentifier ?? "pid \(owner)"
        }

        return Array(Set(names)).sorted()
    }
}
