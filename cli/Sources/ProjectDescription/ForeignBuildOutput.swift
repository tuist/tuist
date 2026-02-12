/// Describes the binary artifact produced by a foreign (non-Xcode) build system.
public enum ForeignBuildOutput: Codable, Hashable, Sendable {
    /// Describes how a binary artifact is linked.
    public enum Linking: String, Codable, Hashable, Sendable {
        case `static`, dynamic
    }

    /// An XCFramework output.
    ///
    /// - Parameters:
    ///   - path: Relative path to the xcframework.
    ///   - linking: Whether the xcframework is statically or dynamically linked.
    case xcframework(path: Path, linking: Linking)

    /// A framework output.
    ///
    /// - Parameters:
    ///   - path: Relative path to the framework.
    ///   - linking: Whether the framework is statically or dynamically linked.
    case framework(path: Path, linking: Linking)

    var product: Product {
        switch self {
        case let .xcframework(_, linking), let .framework(_, linking):
            return linking == .static ? .staticFramework : .framework
        }
    }
}
