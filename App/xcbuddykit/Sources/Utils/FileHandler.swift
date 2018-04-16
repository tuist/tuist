import Foundation
import PathKit

protocol FileHandling: AnyObject {
    var currentPath: Path { get }
    func exists(_ path: Path) -> Bool
    func isRelative(_ path: Path) -> Bool
    func glob(_ path: Path, glob: String) -> [Path]
}

final class FileHandler: FileHandling {
    var currentPath: Path {
        return Path.current
    }

    func exists(_ path: Path) -> Bool {
        return path.exists
    }

    func isRelative(_ path: Path) -> Bool {
        return path.isRelative
    }

    func glob(_ path: Path, glob: String) -> [Path] {
        return path.glob(glob)
    }
}
