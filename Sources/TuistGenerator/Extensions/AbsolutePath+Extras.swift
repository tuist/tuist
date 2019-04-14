import Basic
import Foundation
import PathKit

extension AbsolutePath {
    var path: Path {
        return Path(pathString)
    }
}
