import Foundation
import Path
import PathKit

extension AbsolutePath {
    var path: Path {
        Path(pathString)
    }
}
