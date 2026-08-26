/// Shared metadata tags used by graph mappers.
public enum TargetTags {
    /// Targets generated from Swift package manifests.
    public static let swiftPackage = "tuist:swift-package"

    /// Local path Swift packages loaded through Swift Package Manager are represented as external projects.
    /// This tag allows downstream mappers to preserve only those package test targets.
    public static let localSwiftPackageTest = "tuist:local-swift-package-test"
}
