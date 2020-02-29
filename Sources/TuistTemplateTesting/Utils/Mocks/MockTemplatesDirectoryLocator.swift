import Basic
import Foundation
import TuistTemplate
@testable import TuistKit

public final class MockTemplatesDirectoryLocator: TemplatesDirectoryLocating {
    public var locateStub: (() -> AbsolutePath?)?
    public var locateCustomStub: ((AbsolutePath) -> AbsolutePath?)?
    public var locateFromStub: ((AbsolutePath) -> AbsolutePath?)?
    public var templateDirectoriesStub: (() throws -> [AbsolutePath])?
    
    public func locate() -> AbsolutePath? {
        locateStub?()
    }
    
    public func locateCustom(at: AbsolutePath) -> AbsolutePath? {
        locateCustomStub?(at)
    }
    
    public func locate(from path: AbsolutePath) -> AbsolutePath? {
        locateFromStub?(path)
    }
    
    public func templateDirectories() throws -> [AbsolutePath] {
        try templateDirectoriesStub?() ?? []
    }
    
}
