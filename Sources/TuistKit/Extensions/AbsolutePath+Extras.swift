import Foundation
import Basic
import PathKit

extension AbsolutePath {
    var path: Path {
        return Path(self.asString)
    }
}
