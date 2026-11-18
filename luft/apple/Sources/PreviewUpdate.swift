import Foundation
import MachO
import Security
import SwiftUI

/// A newer internal preview of Luft than the running build, as the Rust core decides it.
struct PreviewUpdate: Decodable, Equatable {
    let id: String
    let version: String?
    let commit: String?
    let install_url: String
}

private struct PreviewUpdateResponse: Decodable {
    let update: PreviewUpdate?
    /// The core suggests each newer build once per launch.
    let suggest: Bool?
}

@MainActor @Observable
final class PreviewUpdater {
    private(set) var update: PreviewUpdate?
    private(set) var installing = false
    /// Whether to ask the person to update now, which keeps them on the latest preview.
    var suggesting = false
    /// iOS took over the install: the app stays open until iOS replaces it.
    private(set) var awaitingInstall = false
    @ObservationIgnored private let client: AppClient

    init(client: AppClient) {
        self.client = client
    }

    /// Asks the core whether tuist.dev has a newer internal preview for this platform.
    /// Failures leave the current state: a missed check only delays the banner.
    func check() async {
        #if targetEnvironment(simulator)
            // The simulator cannot install device builds.
            return
        #else
            guard client.view.active != nil, let binaryID = Self.binaryID else { return }
            #if os(macOS)
                let platform = "macos"
            #else
                let platform = "ios"
            #endif
            guard let data = try? await client.call("preview_update", ["platform": platform, "binary_id": binaryID]),
                  let response = try? JSONDecoder().decode(
                      PreviewUpdateResponse.self, from: JSONSerialization.data(withJSONObject: data)
                  )
            else { return }
            update = response.update
            if response.suggest == true { suggesting = true }
        #endif
    }

    func install() async {
        guard let update, !installing, let url = URL(string: update.install_url) else { return }
        installing = true
        defer { installing = false }
        #if os(iOS)
            // iOS asks to confirm, then replaces this app from the preview's OTA manifest.
            if await UIApplication.shared.open(url) {
                awaitingInstall = true
            } else {
                client.error = String(localized: "The update could not be installed.")
            }
        #else
            do {
                try await MacInstaller.replaceAndRelaunch(from: url)
            } catch {
                client.error = String(localized: "The update could not be installed.")
            }
        #endif
    }

    /// The running executable's Mach-O UUID: the binary ID `tuist share` records for its preview.
    static let binaryID: String? = {
        guard let header = _dyld_get_image_header(0) else { return nil }
        var command = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
        for _ in 0 ..< header.pointee.ncmds {
            let load = command.load(as: load_command.self)
            if load.cmd == LC_UUID {
                return UUID(uuid: command.load(as: uuid_command.self).uuid).uuidString
            }
            command = command.advanced(by: Int(load.cmdsize))
        }
        return nil
    }()
}

#if os(macOS)
    /// Replaces this app with a downloaded preview after it quits, then reopens it.
    private enum MacInstaller {
        /// Only Tuist's Developer ID builds of this app may replace it.
        private static let requirement =
            #"anchor apple generic and identifier "dev.tuist.code" and certificate leaf[subject.OU] = "U6LC622NKF""#

        static func replaceAndRelaunch(from url: URL) async throws {
            let (archive, response) = try await URLSession.shared.download(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let directory = FileManager.default.temporaryDirectory.appending(path: "LuftUpdate-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try run("/usr/bin/ditto", ["-x", "-k", archive.path, directory.path])
            guard let app = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?
                .compactMap({ $0 as? URL }).first(where: { $0.pathExtension == "app" })
            else { throw CocoaError(.fileReadCorruptFile) }
            try verify(app)
            let current = Bundle.main.bundleURL
            // A detached shell waits for this process to exit, swaps the bundles, and reopens the app.
            let script = """
            while /bin/kill -0 "$0" 2>/dev/null; do /bin/sleep 0.2; done
            /bin/rm -rf "$2.old" && /bin/mv "$2" "$2.old" && /bin/mv "$1" "$2" && /bin/rm -rf "$2.old"
            /usr/bin/open "$2"
            """
            let helper = Process()
            helper.executableURL = URL(filePath: "/bin/sh")
            helper.arguments = ["-c", script, "\(ProcessInfo.processInfo.processIdentifier)", app.path, current.path]
            try helper.run()
            NSApplication.shared.terminate(nil)
        }

        private static func verify(_ app: URL) throws {
            var code: SecStaticCode?
            var requirement: SecRequirement?
            guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
                  SecRequirementCreateWithString(self.requirement as CFString, [], &requirement) == errSecSuccess,
                  SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement)
                  == errSecSuccess
            else { throw CocoaError(.fileReadCorruptFile) }
        }

        private static func run(_ tool: String, _ arguments: [String]) throws {
            let process = Process()
            process.executableURL = URL(filePath: tool)
            process.arguments = arguments
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        }
    }
#endif

/// Profile's row under App version: a newer build with one Update button.
struct PreviewUpdateRow: View {
    let updater: PreviewUpdater

    var body: some View {
        if let update = updater.update {
            LabeledContent {
                if updater.installing {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel(Text("Updating…"))
                } else {
                    Button("Update") { Task { await updater.install() } }
                        .prominentGlassButtonStyle()
                        .controlSize(.small)
                }
            } label: {
                Text("New version available")
                if let commit = update.commit {
                    Text("Build \(commit)").monospaced()
                }
                if updater.awaitingInstall {
                    Text("Confirm the install. iOS closes Luft to finish it.")
                }
            }
        }
    }
}
