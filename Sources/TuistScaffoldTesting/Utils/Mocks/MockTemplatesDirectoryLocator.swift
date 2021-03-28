import Foundation
import TSCBasic
@testable import TuistScaffold

public final class MockTemplatesDirectoryLocator: TemplatesDirectoryLocating {
    public init() {}

    public var locateUserTemplatesStub: ((AbsolutePath) -> AbsolutePath?)?
    public var locateTuistTemplatesStub: (() -> AbsolutePath?)?
    public var templateDirectoriesStub: ((AbsolutePath) throws -> [AbsolutePath])?
    public var templatePluginDirectoriesStub: ((AbsolutePath) throws -> [AbsolutePath])?

    public func locateUserTemplates(at: AbsolutePath) -> AbsolutePath? {
        locateUserTemplatesStub?(at)
    }

    public func locateTuistTemplates() -> AbsolutePath? {
        locateTuistTemplatesStub?()
    }

    public func templateDirectories(at path: AbsolutePath) throws -> [AbsolutePath] {
        try templateDirectoriesStub?(path) ?? []
    }

    public func templatePluginDirectories(at path: AbsolutePath) throws -> [AbsolutePath] {
        try templatePluginDirectoriesStub?(path) ?? []
    }
}
