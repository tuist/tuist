import Foundation
import PathKit
import TSCBasic

extension AbsolutePath {
    var path: Path {
        Path(pathString)
    }
}
