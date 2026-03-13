import FileSystem
import Foundation
import Path
import TuistLogging

public enum XcodeError: FatalError, Equatable {
    case infoPlistNotFound(Xcode.PathSource)

    public var description: String {
        switch self {
        case let .infoPlistNotFound(source):
            switch source {
            case let .environment(path):
                return "Couldn't find Xcode's Info.plist at \(path.pathString). This path was set via the environment variable DEVELOPER_DIR."
            case let .xcodeSelect(path):
                return "Couldn't find Xcode's Info.plist at \(path.pathString). Make sure your Xcode installation is selected by running: sudo xcode-select -s /Applications/Xcode.app"
            }
        }
    }

    public var type: ErrorType {
        switch self {
        case .infoPlistNotFound:
            return .abort
        }
    }
}

public struct Xcode {
    public enum PathSource: Equatable {
        case environment(AbsolutePath)
        case xcodeSelect(AbsolutePath)

        var path: AbsolutePath {
            switch self {
            case let .environment(path),
                 let .xcodeSelect(path):
                return path
            }
        }

        func with(path: AbsolutePath) -> Self {
            switch self {
            case .environment:
                return .environment(path)
            case .xcodeSelect:
                return .xcodeSelect(path)
            }
        }
    }

    /// It represents the content of the Info.plist file inside the Xcode app bundle.
    public struct InfoPlist: Codable {
        /// App version number (e.g. 10.3)
        public let version: String

        /// Initializes the InfoPlist object with its attributes.
        ///
        /// - Parameter version: Version.
        public init(version: String) {
            self.version = version
        }

        enum CodingKeys: String, CodingKey {
            case version = "CFBundleShortVersionString"
        }
    }

    /// Path to the Xcode app bundle.
    public let path: AbsolutePath

    /// Info plist content.
    public let infoPlist: InfoPlist

    /// Initializes an Xcode instance by reading it from a local Xcode.app bundle.
    ///
    /// - Parameter source: Path to a local Xcode.app bundle.
    /// - Returns: Initialized Xcode instance.
    /// - Throws: An error if the local installation can't be read.
    static func read(source: PathSource) async throws -> Xcode {
        let infoPlistPath = source.path.appending(try RelativePath(validating: "Contents/Info.plist"))
        let fileSystem = FileSystem()
        if try await !fileSystem.exists(infoPlistPath) {
            throw XcodeError.infoPlistNotFound(source.with(path: infoPlistPath))
        }
        let plistDecoder = PropertyListDecoder()
        let data = try Data(contentsOf: infoPlistPath.url)
        let infoPlist = try plistDecoder.decode(InfoPlist.self, from: data)

        return Xcode(path: source.path, infoPlist: infoPlist)
    }

    /// Initializes an instance of Xcode which represents a local installation of Xcode
    ///
    /// - Parameters:
    ///     - path: Path to the Xcode app bundle.
    ///     - infoPlist: Info plist content.
    public init(
        path: AbsolutePath,
        infoPlist: InfoPlist
    ) {
        self.path = path
        self.infoPlist = infoPlist
    }
}

#if DEBUG
    extension Xcode {
        public static func test(
            path: AbsolutePath = try! AbsolutePath(validating: "/Applications/Xcode.app"), // swiftlint:disable:this force_try
            infoPlist: Xcode.InfoPlist = .test()
        ) -> Xcode {
            Xcode(path: path, infoPlist: infoPlist)
        }
    }

    extension Xcode.InfoPlist {
        public static func test(version: String = "3.2.1") -> Xcode.InfoPlist {
            Xcode.InfoPlist(version: version)
        }
    }
#endif
