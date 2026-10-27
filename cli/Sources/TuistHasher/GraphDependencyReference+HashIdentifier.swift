import Path
import TuistCore
import XcodeGraph

extension GraphDependencyReference {
    /// A deterministic, machine-independent identifier for the reference, used to fold a target's
    /// embedded product closure (resource bundles, embedded frameworks) into its content hash.
    ///
    /// It intentionally derives from product/bundle identity rather than absolute paths, so the hash
    /// stays stable across machines and checkout locations while still changing when the set of
    /// embedded products changes.
    var hashIdentifier: String {
        switch self {
        case let .macro(path):
            return "macro:\(path.basename)"
        case let .foreignBuildOutput(path, linking, _):
            return "foreignBuildOutput:\(path.basename):\(linking)"
        case let .xcframework(path, _, _, _, _):
            return "xcframework:\(path.basename)"
        case let .library(path, linking, _, product, _):
            return "library:\(path.basename):\(product.rawValue):\(linking)"
        case let .framework(path, _, _, _, linking, _, product, _, _):
            return "framework:\(path.basename):\(product.rawValue):\(linking)"
        case let .bundle(path, _):
            return "bundle:\(path.basename)"
        case let .product(target, productName, _, _):
            return "product:\(target):\(productName)"
        case let .sdk(path, _, source, _):
            return "sdk:\(path.basename):\(source)"
        case let .packageProduct(product, _):
            return "packageProduct:\(product)"
        }
    }
}
