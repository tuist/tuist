import TSCBasic
import TuistCore
import TuistGraph

public final class MockXcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating {
    public init() {}

    // swiftlint:disable:next type_name
    enum MockXcodeProjectBuildDirectoryLocatorError: Error {
        case noStub
    }

    public var locateStub: ((Platform, AbsolutePath, AbsolutePath?, String) throws -> AbsolutePath)?
    public func locate(
        platform: Platform,
        projectPath: AbsolutePath,
        derivedDataPath: AbsolutePath?,
        configuration: String
    ) throws -> AbsolutePath {
        guard let stub = locateStub else {
            throw MockXcodeProjectBuildDirectoryLocatorError.noStub
        }
        return try stub(platform, projectPath, derivedDataPath, configuration)
    }
}
