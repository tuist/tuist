import CryptoKit
import FileSystem
import Foundation
import Path
import TuistCore
import XcodeGraph

public enum BinaryCacheArtifact {
    public static func coverage(
        at path: AbsolutePath,
        fileSystem: FileSysteming = FileSystem()
    ) async throws -> [String: Set<String>] {
        let data = try await fileSystem.readFile(at: path.appending(component: "Info.plist"))
        let info = try PropertyListDecoder().decode(XCFrameworkInfoPlist.self, from: data)
        var result: [String: Set<String>] = [:]
        for variant in BinaryCacheVariant.allCases {
            guard let library = info.libraries.first(where: { variant.matches($0) }) else { continue }
            let libraryPath = path.appending(component: library.identifier).appending(library.path)
            let binaryPath = libraryPath.extension == "framework"
                ? libraryPath.appending(component: libraryPath.basenameWithoutExt) : libraryPath
            guard try await fileSystem.exists(binaryPath) else { continue }
            result[variant.rawValue] = Set(library.architectures.map(\.rawValue))
        }
        return result
    }
}
