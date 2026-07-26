import Foundation
import ResourceLoader

public enum StaticFrameworkAssets {
    /// `#bundle` expands here, in this module's context, via SE-0422 caller-side default arguments.
    public static func implicitBundleResourceURL() -> URL? {
        ResourceLoading.resourceURL(named: "data")
    }

    public static func directBundleMacroResourceURL() -> URL? {
        #bundle.url(forResource: "data", withExtension: "json")
    }

    public static func explicitModuleResourceURL() -> URL? {
        ResourceLoading.resourceURL(named: "data", bundle: .module)
    }
}
