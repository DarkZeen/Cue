import AppKit
import Foundation
import Observation
import Security

/// Keeping Cue up to date, without Sparkle.
///
/// Sparkle is the conventional answer and it is a very good one. It is also a
/// third-party dependency, and this project has none by standing decision — so
/// this is the small version: ask GitHub what the latest release is, download
/// it, refuse to install anything not signed by the same identity as the copy
/// asking, swap it in, relaunch.
///
/// The signature check is the part that matters. An updater that downloads code
/// and runs it is a remote execution facility; the only thing separating it from
/// a bad one is that it will not install a bundle that fails the running app's
/// own designated requirement.
@Observable
final class UpdateService {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, notes: String)
        case downloading(progress: Double)
        case readyToRelaunch
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var lastChecked: Date?

    /// Where releases come from. The repository is Cue's own; an updater that
    /// could be pointed elsewhere is a back door with a settings row.
    private static let releasesURL = URL(
        string: "https://api.github.com/repos/DarkZeen/Cue/releases/latest"
    )!

    private let settings: SettingsStore
    private let logger = Diagnostics.logger("updates")
    private var downloaded: URL?
    private var scheduled: Task<Void, Never>?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: - Scheduling

    /// Checks shortly after launch, then once a day.
    ///
    /// Not at the moment of launch: the first seconds belong to the player
    /// warming up and the library loading, and an update check competing with
    /// those buys nothing — nobody is waiting for it.
    func startChecking() {
        guard settings.checksForUpdates else { return }

        scheduled?.cancel()
        scheduled = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            while !Task.isCancelled {
                await self?.check(userInitiated: false)
                try? await Task.sleep(for: .seconds(24 * 60 * 60))
            }
        }
    }

    func stopChecking() {
        scheduled?.cancel()
        scheduled = nil
    }

    // MARK: - Checking

    func check(userInitiated: Bool) async {
        if case .downloading = state { return }
        state = .checking

        do {
            var request = URLRequest(url: Self.releasesURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            // GitHub refuses anonymous API requests without one.
            request.setValue("Cue/\(currentVersion)", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            guard status == 200 else {
                // 404 is the ordinary state of a repository with no releases
                // yet, and saying "update failed" for that would be a lie.
                state = status == 404 ? .upToDate : .failed("GitHub returned \(status).")
                return
            }

            let release = try JSONDecoder().decode(Release.self, from: data)
            lastChecked = Date()

            let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            guard Self.isNewer(latest, than: currentVersion) else {
                logger.notice("Up to date at \(self.currentVersion, privacy: .public).")
                state = .upToDate
                return
            }

            guard release.zipAsset != nil else {
                state = .failed("Release \(latest) has no download.")
                return
            }

            logger.notice("Update available: \(latest, privacy: .public).")
            state = .available(version: latest, notes: release.body ?? "")

            if settings.checksForUpdates, !userInitiated {
                await download(release)
            }
        } catch {
            logger.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    /// Fetches, verifies and stages an update. It is not installed until asked.
    func download(_ release: Release) async {
        guard let asset = release.zipAsset else { return }
        state = .downloading(progress: 0)

        do {
            let (fileURL, _) = try await URLSession.shared.download(from: asset)

            let workspace = FileManager.default.temporaryDirectory
                .appendingPathComponent("cue-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

            let archive = workspace.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: fileURL, to: archive)

            try Self.expand(archive, into: workspace)

            guard let app = try Self.findApp(in: workspace) else {
                throw Failure.noApplicationInArchive
            }

            try Self.verifySignature(of: app)

            downloaded = app
            state = .readyToRelaunch
            logger.notice("Update staged and verified.")
        } catch {
            logger.error("Update download failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    /// Swaps the new build in and restarts.
    func installAndRelaunch() {
        guard let downloaded else { return }

        let target = Bundle.main.bundleURL

        do {
            // `replaceItemAt` swaps the directories rather than deleting and
            // copying, so a failure part-way leaves the working copy in place
            // rather than half an application.
            _ = try FileManager.default.replaceItemAt(target, withItemAt: downloaded)

            // Relaunching cannot be done from inside a process that is about to
            // stop existing, so a detached shell waits for this one to go and
            // opens the new copy.
            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
            relaunch.arguments = [
                "-c",
                "sleep 1; /usr/bin/open \"\(target.path)\"",
            ]
            try relaunch.run()

            logger.notice("Installed; relaunching.")
            NSApp.terminate(nil)
        } catch {
            logger.error("Update install failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(
                "Could not replace \(target.lastPathComponent). If Cue is in /Applications, try moving it to your home folder."
            )
        }
    }

    // MARK: - Steps

    private static func expand(_ archive: URL, into directory: URL) throws {
        // `ditto` rather than an unzip library: it is the tool macOS itself uses
        // for this, and it preserves the extended attributes and symlinks an
        // application bundle needs to stay signed.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, directory.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { throw Failure.couldNotExpand }
    }

    private static func findApp(in directory: URL) throws -> URL? {
        try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .first { $0.pathExtension == "app" }
    }

    /// Refuses anything not signed by whoever signed the running copy.
    ///
    /// The whole safety of this feature. Without it Cue would download a zip
    /// from the internet and execute it, and the only thing standing between
    /// that and a compromised machine would be GitHub's account security.
    private static func verifySignature(of candidate: URL) throws {
        var running: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &running) == errSecSuccess,
              let running
        else { throw Failure.cannotReadOwnSignature }

        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(running, [], &requirement) == errSecSuccess,
              let requirement
        else { throw Failure.cannotReadOwnSignature }

        var incoming: SecStaticCode?
        guard SecStaticCodeCreateWithPath(candidate as CFURL, [], &incoming) == errSecSuccess,
              let incoming
        else { throw Failure.unsigned }

        let status = SecStaticCodeCheckValidity(incoming, [], requirement)
        guard status == errSecSuccess else { throw Failure.signatureMismatch }
    }

    /// Compares dotted versions numerically, so 0.10.0 is newer than 0.9.0 —
    /// which string comparison gets backwards.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let right = current.split(separator: ".").map { Int($0) ?? 0 }

        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    // MARK: - Wire types

    struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let body: String?
        let assets: [Asset]

        var zipAsset: URL? {
            assets.first { $0.name.hasSuffix(".zip") }?.browserDownloadURL
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body
            case assets
        }
    }

    enum Failure: Error, LocalizedError {
        case couldNotExpand
        case noApplicationInArchive
        case unsigned
        case signatureMismatch
        case cannotReadOwnSignature

        var errorDescription: String? {
            switch self {
            case .couldNotExpand: "The download could not be opened."
            case .noApplicationInArchive: "The download contained no application."
            case .unsigned: "The download is not signed."
            case .signatureMismatch:
                "The download is signed by someone else and was discarded."
            case .cannotReadOwnSignature:
                "Cue could not read its own signature, so it cannot check the update's."
            }
        }
    }
}
