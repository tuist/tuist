import Basic
import Foundation
import PathKit

extension AbsolutePath {
    var path: Path {
        Path(pathString)
    }
}
