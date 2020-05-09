import Foundation
import TSCBasic

enum ValueGraphDependency: Hashable {
    case xcframework(path: AbsolutePath, infoPlist: XCFrameworkInfoPlist, primaryBinaryPath: AbsolutePath, linking: BinaryLinking)
    case framework(path: AbsolutePath, dsymPath: AbsolutePath?, bcsymbolmapPaths: [AbsolutePath], linking: BinaryLinking, architectures: [BinaryArchitecture])
    case library(path: AbsolutePath, publicHeaders: AbsolutePath, architectures: [BinaryArchitecture], linking: BinaryLinking, swiftModuleMap: AbsolutePath?)
    case packageProduct(product: String, path: AbsolutePath)
    case target(name: String, path: AbsolutePath)
    
    func hash(into hasher: inout Hasher) {
        switch self {
        case .framework(let path, _, _, _, _):
            hasher.combine(path)
        case .framework(let path, _, _, _, _):
            hasher.combine(path)
        case .library(let path, _, _, _, _):
            hasher.combine(path)
        case .packageProduct(let product, let path):
            
        }
    }
}
