import Foundation

public enum ResourceLoading {
    /// The `#bundle` default argument expands at the call site (SE-0422), so the resource is
    /// looked up in the calling module's bundle.
    public static func resourceURL(named name: String, bundle: Bundle = #bundle) -> URL? {
        bundle.url(forResource: name, withExtension: "json")
    }
}
