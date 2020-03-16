import Basic
import Foundation
@testable import TuistScaffold

public final class MockTemplatesDirectoryLocator: TemplatesDirectoryLocating {
    public var locateCustomStub: ((AbsolutePath) -> AbsolutePath?)?
    public var templateDirectoriesStub: ((AbsolutePath) throws -> [AbsolutePath])?

    public func locateCustom(at: AbsolutePath) -> AbsolutePath? {
        locateCustomStub?(at)
    }

    public func templateDirectories(at path: AbsolutePath) throws -> [AbsolutePath] {
        try templateDirectoriesStub?(path) ?? []
    }
}
