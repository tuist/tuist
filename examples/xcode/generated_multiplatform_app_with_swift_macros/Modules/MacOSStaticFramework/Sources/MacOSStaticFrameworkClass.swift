import Foundation
import MultiPlatformTransitiveDynamicFramework

public class MacOSStaticFrameworkClass {
    var logoURL: URL?

    public init() {
        logoURL = Bundle.module.url(forResource: "logo", withExtension: "png")
    }

    public func print() {
        MultiPlatformTransitiveDynamicFrameworkClass().print()
        Swift.print("MacOSStaticFramework")
    }
}
