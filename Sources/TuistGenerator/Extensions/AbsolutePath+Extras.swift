import Foundation
import PathKit
import Path

extension AbsolutePath {
    var path: Path {
        Path(pathString)
    }
}
