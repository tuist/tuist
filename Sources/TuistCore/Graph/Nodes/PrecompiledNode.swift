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

    /// - Returns: True if node is dynamic and linkable
    public func isDynamicAndLinkable() -> Bool {
        if let framework = self as? FrameworkNode { return framework.linking == .dynamic }
        if let xcframework = self as? XCFrameworkNode { return xcframework.linking == .dynamic }
        return false
    }

    enum CodingKeys: String, CodingKey {
        case path
        case name
        case architectures
        case product
        case type
    }
}
