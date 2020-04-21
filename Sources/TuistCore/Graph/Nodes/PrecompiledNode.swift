import Foundation
import TSCBasic
import TuistSupport

public class PrecompiledNode: GraphNode {
    public init(path: AbsolutePath) {
        /// Returns the name of the precompiled node removing the extension
        /// Alamofire.framework -> Alamofire
        /// libAlamofire.a -> libAlamofire
        let name = String(path.components.last!.split(separator: ".").first!)
        super.init(path: path, name: name)
    }

    public var binaryPath: AbsolutePath {
        fatalError("This method should be overriden by the subclasses")
    }

    enum CodingKeys: String, CodingKey {
        case path
        case name
        case architectures
        case product
        case type
    }
}
