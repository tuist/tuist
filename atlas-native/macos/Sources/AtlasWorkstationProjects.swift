#if os(macOS)
import CryptoKit
import Foundation

enum AtlasWorkstationProjects {
    static func repository(_ root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path)
    }

    static func metadata(_ roots: [String: URL]) async -> [AtlasEnvironmentProject] {
        await Task.detached(priority: .utility) {
            roots.map { id, root in
                let coding = repository(root)
                return AtlasEnvironmentProject(id: id, name: root.lastPathComponent, coding: coding,
                                               repository: coding ? githubRepository(at: root) : nil)
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }.value
    }

    static func githubRepository(remote: String) -> String? {
        let path: String
        if remote.hasPrefix("git@github.com:") {
            path = String(remote.dropFirst("git@github.com:".count))
        } else if let url = URLComponents(string: remote), url.host?.lowercased() == "github.com",
                  url.query == nil, url.fragment == nil, url.password == nil,
                  url.scheme == "https" && url.user == nil && (url.port == nil || url.port == 443)
                    || url.scheme == "ssh" && url.user == "git" && (url.port == nil || url.port == 22),
                  url.path.hasPrefix("/") {
            path = String(url.path.dropFirst())
        } else { return nil }
        let name = path.hasSuffix(".git") ? String(path.dropLast(4)) : path
        guard name.range(of: "^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_.-]{1,100}$",
                         options: .regularExpression) != nil,
              !name.contains("\n"), !name.contains("\r") else { return nil }
        return name.lowercased()
    }

    private static func githubRepository(at root: URL) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["config", "--local", "--get", "remote.origin.url"]
        process.currentDirectoryURL = root
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardOutput = output.fileHandleForWriting
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
            guard finished.wait(timeout: .now() + 5) == .success else {
                process.terminate()
                if finished.wait(timeout: .now() + 1) == .timedOut { kill(process.processIdentifier, SIGKILL) }
                return nil
            }
            try output.fileHandleForWriting.close()
            guard process.terminationStatus == 0,
                  let data = try output.fileHandleForReading.read(upToCount: 1024), data.count < 1024,
                  let remote = String(data: data, encoding: .utf8) else { return nil }
            return githubRepository(remote: remote.trimmingCharacters(in: .newlines))
        } catch { return nil }
    }

    static func discover(_ configuration: AtlasWorkstationConfiguration) async throws -> [String: URL] {
        try await Task.detached(priority: .utility) {
            var roots = Dictionary(uniqueKeysWithValues: configuration.folders.map {
                ($0.id, URL(fileURLWithPath: $0.path).resolvingSymlinksInPath())
            })
            if configuration.home { roots[configuration.homeId] = FileManager.default.homeDirectoryForCurrentUser }
            for parent in configuration.projectDirectories {
                let url = URL(fileURLWithPath: parent.path).resolvingSymlinksInPath()
                let enumerator = FileManager.default.enumerator(
                    at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
                )
                var count = 0
                while let child = enumerator?.nextObject() as? URL {
                    count += 1
                    guard count <= 1000, roots.count < 100 else { break }
                    let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    guard values.isDirectory == true, values.isSymbolicLink != true, repository(child) else { continue }
                    let digest = SHA256.hash(data: Data((parent.id + ":" + child.lastPathComponent).utf8))
                    let bytes = Array(digest.prefix(16))
                    let id = UUID(uuid: (
                        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                        bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
                    ))
                    roots[id.uuidString.lowercased()] = child
                }
            }
            guard roots.count <= 100 else { throw CocoaError(.fileReadTooLarge) }
            return roots
        }.value
    }
}
#endif
