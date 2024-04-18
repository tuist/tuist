import Foundation

// Public Accessors

@objc
public class StylesResources: NSObject {
    @objc public class var bundle: Bundle {
        return .module
    }
}

#if !SIWFT_PACKAGE
    private class BundleFinder {}
    extension Foundation.Bundle {
        static let module = Bundle(for: BundleFinder.self)
    }
#endif
