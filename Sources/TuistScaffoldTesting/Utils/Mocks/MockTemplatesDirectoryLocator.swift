import Basic
import Foundation
@testable import TuistScaffold

public final class MockTemplatesDirectoryLocator: TemplatesDirectoryLocating {
    public var locateUserTemplatesStub: ((AbsolutePath) -> AbsolutePath?)?
    public var templateDirectoriesStub: ((AbsolutePath) throws -> [AbsolutePath])?

    public func locateUserTemplates(at: AbsolutePath) -> AbsolutePath? {
        locateUserTemplatesStub?(at)
    }

    public func templateDirectories(at path: AbsolutePath) throws -> [AbsolutePath] {
        try templateDirectoriesStub?(path) ?? []
    }
}
