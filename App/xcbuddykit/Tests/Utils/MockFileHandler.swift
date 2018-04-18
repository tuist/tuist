import Foundation
import Basic

@testable import xcbuddykit

final class MockFileHandler: FileHandling {
    
    var existsStub: ((AbsolutePath) -> Bool)?
    var currentPathStub: AbsolutePath?
    var globStub: ((AbsolutePath, String) -> [AbsolutePath])?
    
    var currentPath: AbsolutePath {
        return currentPathStub ?? AbsolutePath.current
    }

    func exists(_ path: AbsolutePath) -> Bool {
        return existsStub?(path) ?? false
    }

    func glob(_ path: AbsolutePath, glob: String) -> [AbsolutePath] {
        return globStub?(path, glob) ?? []
    }
}
