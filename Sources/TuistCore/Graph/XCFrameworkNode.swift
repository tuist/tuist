import Basic
import Foundation
import TuistSupport

public class XCFrameworkNode: PrecompiledNode {
    enum XCFrameworkNodeCodingKeys: String, CodingKey {
        case libraries
    }

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
        primaryBinaryPath
    }

    public override func encode(to encoder: Encoder) throws {
        var parentContainer = encoder.container(keyedBy: CodingKeys.self)
        try parentContainer.encode(path.pathString, forKey: .path)
        try parentContainer.encode(name, forKey: .name)
        try parentContainer.encode("precompiled", forKey: .type)
        var container = encoder.container(keyedBy: XCFrameworkNodeCodingKeys.self)
        try container.encode(libraries, forKey: .libraries)
    }
}
