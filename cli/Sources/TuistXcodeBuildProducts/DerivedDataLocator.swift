import Crypto
import FileSystem
import Foundation
import Mockable
import Path
import TuistEnvironment

@Mockable
public protocol DerivedDataLocating {
    func locate(
        for projectPath: AbsolutePath
    ) async throws -> AbsolutePath
}

public struct DerivedDataLocator: DerivedDataLocating {
    private let fileSystem: FileSysteming

    public init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    public func locate(
        for projectPath: AbsolutePath
    ) async throws -> AbsolutePath {
        let root: AbsolutePath
        let usesHash: Bool
        let location: DerivedDataLocation
        if let workspaceLocation = try await workspaceDerivedDataLocation(for: projectPath) {
            location = workspaceLocation
        } else {
            location = try await Environment.current.derivedDataLocation()
        }
        switch location {
        case .default:
            root = try await Environment.current.derivedDataDirectory()
            usesHash = true
        case let .custom(path):
            root = path
            usesHash = true
        case let .relativeToWorkspace(relativePath):
            root = projectPath.parentDirectory.appending(relativePath)
            usesHash = false
        }

        // When `inspect` runs as an Xcode build/test post-action, these variables point directly
        // at the build's derived data and take precedence over the location inferred from Xcode's
        // preferences.
        if let derivedDataDir = Environment.current.variables["DERIVED_DATA_DIR"] {
            let path = try AbsolutePath(validating: derivedDataDir)
            if path != root {
                return path
            }
        }
        if let buildDir = Environment.current.variables["BUILD_DIR"],
           let buildRoot = Self.derivedDataRoot(from: buildDir)
        {
            return buildRoot
        }

        let name = xcodeDerivedDataPrefix(for: projectPath)
        if usesHash {
            let hash = try XcodeProjectPathHasher.hashString(for: projectPath.pathString)
            return root.appending(component: "\(name)-\(hash)")
        } else {
            return root.appending(component: name)
        }
    }

    private func workspaceDerivedDataLocation(for projectPath: AbsolutePath) async throws -> DerivedDataLocation? {
        let workspacePath = projectPath.basename.hasSuffix(".xcodeproj")
            ? projectPath.appending(component: "project.xcworkspace") : projectPath
        let settingsPath = workspacePath.appending(
            components: "xcuserdata", "\(NSUserName()).xcuserdatad", "WorkspaceSettings.xcsettings"
        )
        guard try await fileSystem.exists(settingsPath) else { return nil }
        let settings: WorkspaceDerivedDataSettings = try await fileSystem.readPlistFile(at: settingsPath)
        guard let customLocation = settings.customLocation, !customLocation.isEmpty else { return nil }
        switch settings.locationStyle {
        case "AbsolutePath":
            return .custom(try AbsolutePath(validating: customLocation))
        case "WorkspaceRelativePath":
            return .relativeToWorkspace(try RelativePath(validating: customLocation))
        default:
            return nil
        }
    }

    private struct WorkspaceDerivedDataSettings: Decodable {
        let locationStyle: String?
        let customLocation: String?

        enum CodingKeys: String, CodingKey {
            case locationStyle = "DerivedDataLocationStyle"
            case customLocation = "DerivedDataCustomLocation"
        }
    }

    private func xcodeDerivedDataPrefix(for projectPath: AbsolutePath) -> String {
        projectPath.basenameWithoutExt.replacingOccurrences(of: " ", with: "_")
    }

    /// Extracts the derived data root from `BUILD_DIR`.
    /// `BUILD_DIR` is typically `<derived-data-root>/Build/Products/<Configuration>[-<SDK>]`.
    private static func derivedDataRoot(from buildDir: String) -> AbsolutePath? {
        guard let path = try? AbsolutePath(validating: buildDir) else { return nil }
        var current = path
        while !current.isRoot {
            if current.basename == "Products", current.parentDirectory.basename == "Build" {
                return current.parentDirectory.parentDirectory
            }
            current = current.parentDirectory
        }
        return nil
    }
}

// Thanks to https://pewpewthespells.com/blog/xcode_deriveddata_hashes.html for
// the initial Objective-C implementation.
// This is taken from XCLogParser, from Spotify, at:
// https://github.com/spotify/XCLogParser/blob/master/Sources/XcodeHasher/XcodeHasher.swift

enum XcodeProjectPathHasher {
    enum HashingError: Error {
        case invalidPartitioning
    }

    static func hashString(for path: String) throws -> String {
        // Initialize a 28 `String` array since we can't initialize empty `Character`s.
        var result = Array(repeating: "", count: 28)

        let md5 = Insecure.MD5.hash(data: path.data(using: .utf8) ?? Data())
        let digest = Array(md5)

        // Split 16 bytes into two chunks of 8 bytes each.
        let partitions = stride(from: 0, to: digest.count, by: 8).map {
            Array(digest[$0 ..< Swift.min($0 + 8, digest.count)])
        }

        guard let firstHalf = partitions.first,
              let secondHalf = partitions.last
        else {
            throw HashingError.invalidPartitioning
        }

        // We would need to reverse the bytes, so we just read them in big endian.
        var startValue = UInt64(bigEndian: Data(firstHalf).withUnsafeBytes { $0.load(as: UInt64.self) })

        for index in stride(from: 13, through: 0, by: -1) {
            // Take the startValue % 26 to restrict to alphabetic characters and add 'a' scalar value (97).
            let char = String(UnicodeScalar(Int(startValue % 26) + 97)!)
            result[index] = char
            startValue /= 26
        }

        // We would need to reverse the bytes, so we just read them in big endian.
        startValue = UInt64(bigEndian: Data(secondHalf).withUnsafeBytes { $0.load(as: UInt64.self) })

        for index in stride(from: 27, through: 14, by: -1) {
            // Take the startValue % 26 to restrict to alphabetic characters and add 'a' scalar value (97).
            let char = String(UnicodeScalar(Int(startValue % 26) + 97)!)
            result[index] = char
            startValue /= 26
        }

        return result.joined()
    }
}
