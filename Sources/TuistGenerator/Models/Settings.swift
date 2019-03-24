import Basic
import Foundation
import TuistCore

public class Configuration: Equatable {
    // MARK: - Attributes

    public let settings: [String: String]
    public let xcconfig: AbsolutePath?

    // MARK: - Init

    public init(settings: [String: String] = [:], xcconfig: AbsolutePath? = nil) {
        self.settings = settings
        self.xcconfig = xcconfig
    }

    public init(json: JSON, projectPath: AbsolutePath, fileHandler _: FileHandling) throws {
        settings = try json.get("settings")
        let xcconfigString: String? = json.get("xcconfig")
        xcconfig = xcconfigString.flatMap { projectPath.appending(RelativePath($0)) }
    }

    // MARK: - Equatable

    public static func == (lhs: Configuration, rhs: Configuration) -> Bool {
        return lhs.settings == rhs.settings && lhs.xcconfig == rhs.xcconfig
    }
}

public class Settings: Equatable {
    // MARK: - Attributes

    public let base: [String: String]
    public let debug: Configuration?
    public let release: Configuration?

    // MARK: - Init

    public init(base: [String: String] = [:],
                debug: Configuration?,
                release: Configuration?) {
        self.base = base
        self.debug = debug
        self.release = release
    }

    // MARK: - Equatable

    public static func == (lhs: Settings, rhs: Settings) -> Bool {
        return lhs.debug == rhs.debug &&
            lhs.release == rhs.release &&
            lhs.base == rhs.base
    }
}
