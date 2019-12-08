import Basic
import Foundation
import TuistSupport

public class XCFrameworkNode: PrecompiledNode {
    
    public let libraries: [XCFrameworkInfoPlist.Library]
    public let primaryBinaryPath: AbsolutePath

    public init(
        path: AbsolutePath,
        libraries: [XCFrameworkInfoPlist.Library],
        primaryBinaryPath: AbsolutePath
    ) {
        self.libraries = libraries
        self.primaryBinaryPath = primaryBinaryPath
        super.init(path: path)
    }
    
    public override var binaryPath: AbsolutePath {
        return primaryBinaryPath
    }

    override public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path.pathString, forKey: .path)
        try container.encode(name, forKey: .name)
        try container.encode("precompiled", forKey: .type)
    }
}
