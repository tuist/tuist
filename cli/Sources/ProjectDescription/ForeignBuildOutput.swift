/// Describes the binary artifact produced by a foreign (non-Xcode) build system.
public enum ForeignBuildOutput: Codable, Hashable, Sendable {
    /// An XCFramework output.
    ///
    /// - Parameters:
    ///   - path: Relative path to the xcframework.
    ///   - linking: Whether the xcframework is statically or dynamically linked.
    case xcframework(path: Path, linking: BinaryLinking)

    /// A framework output.
    ///
    /// - Parameters:
    ///   - path: Relative path to the framework.
    ///   - linking: Whether the framework is statically or dynamically linked.
    case framework(path: Path, linking: BinaryLinking)

    /// A library output.
    ///
    /// - Parameters:
    ///   - path: Relative path to the library binary.
    ///   - publicHeaders: Relative path to the library's public headers directory.
    ///   - swiftModuleMap: Relative path to the library's Swift module map file.
    ///   - linking: Whether the library is statically or dynamically linked.
    case library(path: Path, publicHeaders: Path, swiftModuleMap: Path?, linking: BinaryLinking)
}
