import Foundation
import UIKit

public class StaticFramework2Resources {
    public let name = "StaticFramework2Resources"
    public init() {}

    public func loadImage() -> UIImage? {
        UIImage(
            named: "StaticFramework2Resources-tuist",
            in: .staticFramework2,
            compatibleWith: nil
        )
    }
}

extension Bundle {
    private class BundleFinder {}

    fileprivate static var staticFramework2: Bundle {
        let hostBundle = Bundle(for: BundleFinder.self)
        let path = hostBundle.path(
            forResource: "StaticFramework2Resources",
            ofType: "bundle"
        )

        guard let bundle = path.flatMap({ Bundle(path: $0) }) else {
            fatalError("StaticFramework2Resources could not be loaded")
        }

        return bundle
    }
}
