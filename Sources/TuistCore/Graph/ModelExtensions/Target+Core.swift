import FileSystem
import Path
import TuistSupport
import XcodeGraph

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
    /// Returns the product name including the extension
    /// if the PRODUCT_NAME build setting of the target is set and contains a static value that's consistent
    /// throughout all the configurations, it uses that value, otherwise it defaults to the target's default.
    public var productNameWithExtension: String {
        var settingsProductNames: Set<String> = Set()

        if let value = settings?.base["PRODUCT_NAME"], case let SettingValue.string(baseProductName) = value {
            settingsProductNames.insert(baseProductName)
        }
        settings?.configurations.values.forEach { configuration in
            if let value = configuration?.settings["PRODUCT_NAME"],
               case let SettingValue.string(configurationProductName) = value
            {
                settingsProductNames.insert(configurationProductName)
            }
        }

        let productName: String

        if settingsProductNames.count == 1, !settingsProductNames.first!.contains("$") {
            productName = settingsProductNames.first!
        } else {
            productName = self.productName
        }

        switch product {
        case .staticLibrary, .dynamicLibrary:
            return "lib\(productName).\(product.xcodeValue.fileExtension!)"
        case .commandLineTool:
            return productName
        case _:
            if let fileExtension = product.xcodeValue.fileExtension {
                return "\(productName).\(fileExtension)"
            } else {
                return productName
            }
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
    public static func sources(
        targetName: String,
        sources: [SourceFileGlob],
        fileSystem: FileSysteming
    ) async throws -> [XcodeGraph.SourceFile] {
        var sourceFiles: [AbsolutePath: XcodeGraph.SourceFile] = [:]
        var invalidGlobs: [InvalidGlob] = []

        for source in sources {
            let sourcePath = try AbsolutePath(validating: source.glob)

            // Paths that should be excluded from sources
            var excluded: [AbsolutePath] = []
            for path in source.excluding {
                let path = try AbsolutePath(validating: path)
                let globs = try await fileSystem.glob(
                    directory: .root,
                    include: [String(path.pathString.dropFirst())]
                )
                .collect()
                excluded.append(contentsOf: globs)
            }

            let paths: [AbsolutePath]

            do {
                paths = try await fileSystem
                    .throwingGlob(directory: .root, include: [String(sourcePath.pathString.dropFirst())])
                    .collect()
                    .filter { !$0.isInOpaqueDirectory }
            } catch let GlobError.nonExistentDirectory(invalidGlob) {
                paths = []
                invalidGlobs.append(invalidGlob)
            }

            Set(paths)
                .subtracting(excluded)
                .filter { path in
                    guard let `extension` = path.extension else { return false }

                    let hasValidSourceExtensions = Target.validSourceExtensions
                        .contains(where: { $0.caseInsensitiveCompare(`extension`) == .orderedSame })

                    if hasValidSourceExtensions {
                        // Addition check to prevent folders with name like `Foo.Swift` to be considered as source files.
                        return !FileHandler.shared.isFolder(path)
                    } else {
                        // There are extensions should be considered as source files even if they are folders.
                        return Target.validSourceCompatibleFolderExtensions
                            .contains(where: { $0.caseInsensitiveCompare(`extension`) == .orderedSame })
                    }
                }
                .forEach { sourceFiles[$0] = SourceFile(
                    path: $0,
                    compilerFlags: source.compilerFlags,
                    codeGen: source.codeGen,
                    compilationCondition: source.compilationCondition
                ) }
        }

        if !invalidGlobs.isEmpty {
            throw TargetError.invalidSourcesGlob(targetName: targetName, invalidGlobs: invalidGlobs)
        }

        return Array(sourceFiles.values)
    }

    public var containsResources: Bool {
        !resources.resources.isEmpty || !coreDataModels.isEmpty
    }

    /// Returns if target is a generated resources bundle.
    public var isGeneratedResourcesBundle: Bool {
        guard product == .bundle else { return false }
        return bundleId.hasSuffix(".generated.resources")
    }
}
