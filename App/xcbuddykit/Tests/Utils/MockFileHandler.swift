import Foundation
import PathKit
@testable import xcbuddykit

final class MockFileHandler: FileHandling {
    var existsStub: ((Path) -> Bool)?
    var isRelativeStub: ((Path) -> Bool)?
    var currentPathStub: Path?
    var globStub: ((Path, String) -> [Path])?
    var currentPath: Path {
        return currentPathStub ?? Path.current
    }

    func exists(_ path: Path) -> Bool {
        return existsStub?(path) ?? false
    }

    func isRelative(_ path: Path) -> Bool {
        return isRelativeStub?(path) ?? false
    }

    func glob(_ path: Path, glob: String) -> [Path] {
        return globStub?(path, glob) ?? []
    }
}
