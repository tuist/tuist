import Basic
import Foundation

public protocol XCFrameworkParsing {
    static func parse(path: AbsolutePath, cache: GraphLoaderCaching) throws -> XCFrameworkNode
}

struct XCFrameworkParser: XCFrameworkParsing {
    static func parse(path: AbsolutePath, cache: GraphLoaderCaching) throws -> XCFrameworkNode {
        if let xcframeworkNode = cache.precompiledNode(path) as? XCFrameworkNode {
            return xcframeworkNode
        }

        let metadataProvider = XCFrameworkMetadataProvider()
        let libraries = try metadataProvider.libraries(frameworkPath: path)
        let binaryPath = try metadataProvider.binaryPath(frameworkPath: path, libraries: libraries)

        let xcframeworkNode = XCFrameworkNode(
            path: path,
            libraries: libraries,
            primaryBinaryPath: binaryPath
        )
        cache.add(precompiledNode: xcframeworkNode)
        return xcframeworkNode
    }
}
