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
        let bundleUrl = Bundle.main.privateFrameworksURL?.appendingPathComponent("StaticFramework2.framework")
        let hostBundle = bundleUrl.flatMap(Bundle.init(url:))
        let path = hostBundle?.path(
            forResource: "StaticFramework2Resources",
            ofType: "bundle"
        )

        guard let bundle = path.flatMap(Bundle.init(path:)) else {
            fatalError("StaticFramework2Resources could not be loaded")
        }

        return bundle
    }
}
