import Path

public struct ForeignBuild: Equatable, Hashable, Codable, Sendable {
    public let inputs: [Input]

    /// The directory the build scripts run in. `nil` runs them in the project directory.
    public let workingDirectory: AbsolutePath?

    /// The universal XCFramework build, produced when warming the binary cache.
    public let xcframework: XCFrameworkBuild

    /// The thinner XCFramework build, produced during regular generation. `nil` falls back to the
    /// universal `xcframework` build.
    public let developmentXCFramework: XCFrameworkBuild?

    public init(
        inputs: [Input],
        workingDirectory: AbsolutePath?,
        xcframework: XCFrameworkBuild,
        developmentXCFramework: XCFrameworkBuild?
    ) {
        self.inputs = inputs
        self.workingDirectory = workingDirectory
        self.xcframework = xcframework
        self.developmentXCFramework = developmentXCFramework
    }

    public enum Input: Equatable, Hashable, Codable, Sendable {
        case file(AbsolutePath)
        case folder(AbsolutePath)
        case script(String)
    }

    /// An XCFramework build: the script that produces it and where it lands.
    public struct XCFrameworkBuild: Equatable, Hashable, Codable, Sendable {
        public let script: String
        public let path: AbsolutePath
        public let linking: BinaryLinking

        public init(script: String, path: AbsolutePath, linking: BinaryLinking) {
            self.script = script
            self.path = path
            self.linking = linking
        }
    }
}
