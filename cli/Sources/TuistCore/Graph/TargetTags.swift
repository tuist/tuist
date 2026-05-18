/// Shared metadata tags used by graph mappers.
public enum TargetTags {
    /// Local path Swift packages loaded through SwiftPM are represented as external projects.
    /// This tag allows downstream mappers to preserve only those package test targets.
    public static let localSwiftPackageTest = "tuist:local-swift-package-test"
}
