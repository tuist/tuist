import Basic
import Foundation
import TuistSupport

public class FrameworkNode: PrecompiledNode {
    public var isCarthage: Bool {
        path.pathString.contains("Carthage/Build")
    }

    /// Return the framework's binary path.
    public override var binaryPath: AbsolutePath {
        FrameworkNode.binaryPath(frameworkPath: path)
    }

    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let metadataProvider = FrameworkMetadataProvider()

        try container.encode(path.pathString, forKey: .path)
        try container.encode(name, forKey: .name)
        try container.encode(try metadataProvider.product(framework: self), forKey: .product)
        let archs = try metadataProvider.architectures(precompiled: self)
        try container.encode(archs.map(\.rawValue), forKey: .architectures)
        try container.encode("precompiled", forKey: .type)
    }

    /// Given a framework path it returns the path to its binary.
    /// - Parameter frameworkPath: Framework path.
    static func binaryPath(frameworkPath: AbsolutePath) -> AbsolutePath {
        let frameworkName = frameworkPath.basename.replacingOccurrences(of: ".framework", with: "")
        return frameworkPath.appending(component: frameworkName)
    }
}
