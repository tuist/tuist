#if os(macOS)
import CryptoKit
import Foundation

enum AtlasWorkstationProjects {
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
                    guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
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
