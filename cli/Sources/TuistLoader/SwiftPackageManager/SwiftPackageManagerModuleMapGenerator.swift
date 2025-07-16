import FileSystem
import Path
import TuistCore
import TuistSupport

/// The type of modulemap file
public enum ModuleMap: Equatable {
    /// No headers and hence no modulemap file
    case none
    /// Custom modulemap file provided in SPM package
    case custom(AbsolutePath, umbrellaHeaderPath: AbsolutePath?)
    /// Umbrella header provided in SPM package
    case header(AbsolutePath, moduleMapPath: AbsolutePath)
    /// No umbrella header provided in SPM package, define umbrella directory
    case directory(moduleMapPath: AbsolutePath, umbrellaDirectory: AbsolutePath)

    var moduleMapPath: AbsolutePath? {
        switch self {
        case let .custom(path, umbrellaHeaderPath: _):
            return path
        case let .header(_, moduleMapPath: path):
            return path
        case let .directory(moduleMapPath: path, umbrellaDirectory: _):
            return path
        case .none:
            return nil
        }
    }

    /// Name of the module map file recognized by the Clang and Swift compilers.
    public static let filename = "module.modulemap"
}

/// Protocol that allows to generate a modulemap for an SPM target.
/// It implements the Swift Package Manager logic
/// [documented here](https://github.com/apple/swift-package-manager/blob/main/Documentation/Usage.md#creating-c-language-targets)
/// and
/// [implemented here](https://github.com/apple/swift-package-manager/blob/main/Sources/PackageLoading/ModuleMapGenerator.swift).
public protocol SwiftPackageManagerModuleMapGenerating {
    func generate(
        packageDirectory: AbsolutePath,
        moduleName: String,
        publicHeadersPath: AbsolutePath
    ) async throws -> ModuleMap
}

public final class SwiftPackageManagerModuleMapGenerator: SwiftPackageManagerModuleMapGenerating {
    private let contentHasher: ContentHashing
    private let fileSystem: FileSysteming

    public init(
        contentHasher: ContentHashing = ContentHasher(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.contentHasher = contentHasher
        self.fileSystem = fileSystem
    }

    // swiftlint:disable:next function_body_length
    public func generate(
        packageDirectory: AbsolutePath,
        moduleName: String,
        publicHeadersPath: AbsolutePath
    ) async throws -> ModuleMap {
        let sanitizedModuleName = moduleName.sanitizedModuleName
        let umbrellaHeaderPath = publicHeadersPath.appending(component: sanitizedModuleName + ".h")
        let nestedUmbrellaHeaderPath = publicHeadersPath
            .appending(components: sanitizedModuleName, sanitizedModuleName + ".h")
        let customModuleMapPath = try await customModuleMapPath(publicHeadersPath: publicHeadersPath)
        let generatedModuleMapPath: AbsolutePath

        if publicHeadersPath.pathString.contains("\(Constants.SwiftPackageManager.packageBuildDirectoryName)/checkouts") {
            generatedModuleMapPath = packageDirectory
                .parentDirectory
                .parentDirectory
                .appending(
                    components: Constants.DerivedDirectory.dependenciesDerivedDirectory,
                    sanitizedModuleName,
                    "\(sanitizedModuleName).modulemap"
                )
        } else {
            generatedModuleMapPath = packageDirectory.appending(
                components: Constants.DerivedDirectory.name, "\(sanitizedModuleName).modulemap"
            )
        }

        if try await !fileSystem.exists(generatedModuleMapPath.parentDirectory) {
            try FileHandler.shared.createFolder(generatedModuleMapPath.parentDirectory)
        }

        if try await fileSystem.exists(umbrellaHeaderPath) {
            if let customModuleMapPath {
                return .custom(customModuleMapPath, umbrellaHeaderPath: umbrellaHeaderPath)
            }
            try await writeIfDifferent(
                moduleMapContent: umbrellaHeaderModuleMap(
                    umbrellaHeaderPath: umbrellaHeaderPath,
                    sanitizedModuleName: sanitizedModuleName
                ),
                to: generatedModuleMapPath,
                atomically: true
            )
            // If 'PublicHeadersDir/ModuleName.h' exists, then use it as the umbrella header.
            return .header(umbrellaHeaderPath, moduleMapPath: generatedModuleMapPath)
        } else if try await fileSystem.exists(nestedUmbrellaHeaderPath) {
            if let customModuleMapPath {
                return .custom(customModuleMapPath, umbrellaHeaderPath: nestedUmbrellaHeaderPath)
            }
            try await writeIfDifferent(
                moduleMapContent: umbrellaHeaderModuleMap(
                    umbrellaHeaderPath: nestedUmbrellaHeaderPath,
                    sanitizedModuleName: sanitizedModuleName
                ),
                to: generatedModuleMapPath,
                atomically: true
            )
            // If 'PublicHeadersDir/ModuleName/ModuleName.h' exists, then use it as the umbrella header.
            return .header(nestedUmbrellaHeaderPath, moduleMapPath: generatedModuleMapPath)
        } else if let customModuleMapPath {
            // User defined modulemap exists, use it
            return .custom(customModuleMapPath, umbrellaHeaderPath: nil)
        } else if try await fileSystem.exists(publicHeadersPath) {
            if try await fileSystem.glob(directory: publicHeadersPath, include: ["**/*.h", "*.h"]).collect().isEmpty {
                return .none
            }
            // Consider the public headers folder as umbrella directory
            let generatedModuleMapContent =
                """
                module \(sanitizedModuleName) {
                    umbrella "\(publicHeadersPath.pathString)"
                    export *
                }
                """
            try await writeIfDifferent(moduleMapContent: generatedModuleMapContent, to: generatedModuleMapPath, atomically: true)

            return .directory(moduleMapPath: generatedModuleMapPath, umbrellaDirectory: publicHeadersPath)
        } else {
            return .none
        }
    }

    /// Write our modulemap to disk if it is distinct from what already exists.
    /// This addresses an issue with dependencies that are included in a precompiled header.
    /// https://github.com/tuist/tuist/issues/6211
    /// - Parameters:
    ///   - moduleMapContent: contents of the moduleMap file to write
    ///   - path: destination to write file contents to
    ///   - atomically: whether to write atomically
    func writeIfDifferent(moduleMapContent: String, to path: AbsolutePath, atomically _: Bool) async throws {
        let newContentHash = try contentHasher.hash(moduleMapContent)
        let currentContentHash = try? await contentHasher.hash(path: path)
        if currentContentHash != newContentHash {
            try FileHandler.shared.write(moduleMapContent, path: path, atomically: true)
        }
    }

    private func customModuleMapPath(publicHeadersPath: AbsolutePath) async throws -> AbsolutePath? {
        guard try await fileSystem.exists(publicHeadersPath) else { return nil }

        let moduleMapPath = try RelativePath(validating: ModuleMap.filename)
        let publicHeadersFolderContent = try FileHandler.shared.contentsOfDirectory(publicHeadersPath)

        if publicHeadersFolderContent.contains(publicHeadersPath.appending(moduleMapPath)) {
            return publicHeadersPath.appending(moduleMapPath)
        } else if publicHeadersFolderContent.count == 1,
                  let nestedHeadersPath = publicHeadersFolderContent.first,
                  FileHandler.shared.isFolder(nestedHeadersPath),
                  try await fileSystem.exists(nestedHeadersPath.appending(moduleMapPath))
        {
            return nestedHeadersPath.appending(moduleMapPath)
        } else {
            return nil
        }
    }

    private func umbrellaHeaderModuleMap(umbrellaHeaderPath: AbsolutePath, sanitizedModuleName: String) -> String {
        """
        framework module \(sanitizedModuleName) {
          umbrella header "\(umbrellaHeaderPath.pathString)"

          export *
          module * { export * }
        }
        """
    }
}
