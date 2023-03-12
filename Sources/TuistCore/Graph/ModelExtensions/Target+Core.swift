import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

public enum TargetError: FatalError, Equatable {
    case invalidSourcesGlob(targetName: String, invalidGlobs: [InvalidGlob])

    public var type: ErrorType { .abort }

    public var description: String {
        switch self {
        case let .invalidSourcesGlob(targetName: targetName, invalidGlobs: invalidGlobs):
            return "The target \(targetName) has the following invalid source files globs:\n" + invalidGlobs
                .invalidGlobsDescription
        }
    }
}

extension Target {
    /// Returns the product name including the extension.
    public var productNameWithExtension: String {
        switch product {
        case .staticLibrary, .dynamicLibrary:
            return "lib\(productName).\(product.xcodeValue.fileExtension!)"
        case .commandLineTool:
            return productName
        case _:
            return "\(productName).\(product.xcodeValue.fileExtension!)"
        }
    }

    /// Returns true if the file at the given path is a resource.
    /// - Parameter path: Path to the file to be checked.
    public static func isResource(path: AbsolutePath) -> Bool {
        if path.isPackage {
            return true
        } else if !FileHandler.shared.isFolder(path) {
            return true
            // We filter out folders that are not Xcode supported bundles such as .app or .framework.
        } else if let `extension` = path.extension, Target.validFolderExtensions.contains(`extension`) {
            return true
        } else {
            return false
        }
    }

    /// This method unfolds the source file globs subtracting the paths that are excluded and ignoring
    /// the files that don't have a supported source extension.
    /// - Parameter sources: List of source file glob to be unfolded.
    public static func sources(targetName: String, sources: [SourceFileGlob]) throws -> [TuistGraph.SourceFile] {
        var sourceFiles: [AbsolutePath: TuistGraph.SourceFile] = [:]
        var invalidGlobs: [InvalidGlob] = []

        try sources.forEach { source in
            let sourcePath = try AbsolutePath(validating: source.glob)
            let base = try AbsolutePath(validating: sourcePath.dirname)

            // Paths that should be excluded from sources
            var excluded: [AbsolutePath] = []
            try source.excluding.forEach { path in
                let absolute = try AbsolutePath(validating: path)
                let globs = try AbsolutePath(validating: absolute.dirname).glob(absolute.basename)
                excluded.append(contentsOf: globs)
            }

            let paths: [AbsolutePath]

            do {
                paths = try FileHandler.shared
                    .throwingGlob(base, glob: sourcePath.basename)
                    .filter { !$0.isInOpaqueDirectory }
            } catch let GlobError.nonExistentDirectory(invalidGlob) {
                paths = []
                invalidGlobs.append(invalidGlob)
            }

            Set(paths)
                .subtracting(excluded)
                .filter { path in
                    guard let `extension` = path.extension else { return false }
                    return Target.validSourceExtensions
                        .contains(where: { $0.caseInsensitiveCompare(`extension`) == .orderedSame })
                }
                .forEach { sourceFiles[$0] = SourceFile(path: $0, compilerFlags: source.compilerFlags, codeGen: source.codeGen) }
        }

        if !invalidGlobs.isEmpty {
            throw TargetError.invalidSourcesGlob(targetName: targetName, invalidGlobs: invalidGlobs)
        }

        return Array(sourceFiles.values)
    }
}
