import TSCBasic
import TuistSupport

/// The type of modulemap file
public enum ModuleMap: Equatable {
    /// No headers and hence no modulemap file
    case none
    /// Custom modulemap file provided in SPM package
    case custom(AbsolutePath, umbrellaHeaderPath: AbsolutePath?)
    /// Umbrella header provided in SPM package
    case header(moduleMapPath: AbsolutePath)
    /// Nested umbrella header provided in SPM package
    case nestedHeader
    /// No umbrella header provided in SPM package, define umbrella directory
    case directory(moduleMapPath: AbsolutePath, umbrellaDirectory: AbsolutePath)

    var moduleMapPath: AbsolutePath? {
        switch self {
        case let .custom(path, umbrellaHeaderPath: _):
            return path
        case let .header(moduleMapPath: path):
            return path
        case let .directory(moduleMapPath: path, umbrellaDirectory: _):
            return path
        case .none, .nestedHeader:
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
    ) throws -> ModuleMap
}

public final class SwiftPackageManagerModuleMapGenerator: SwiftPackageManagerModuleMapGenerating {
    public init() {}

    public func generate(
        packageDirectory: AbsolutePath,
        moduleName: String,
        publicHeadersPath: AbsolutePath
    ) throws -> ModuleMap {
        let umbrellaHeaderPath = publicHeadersPath.appending(component: moduleName + ".h")
        let nestedUmbrellaHeaderPath = publicHeadersPath.appending(component: moduleName).appending(component: moduleName + ".h")
        let sanitizedModuleName = moduleName.replacingOccurrences(of: "-", with: "_")
        let customModuleMapPath = try Self.customModuleMapPath(publicHeadersPath: publicHeadersPath)
        let generatedModuleMapPath: AbsolutePath

        if publicHeadersPath.pathString.contains("\(Constants.SwiftPackageManager.packageBuildDirectoryName)/checkouts") {
            generatedModuleMapPath = packageDirectory
                .parentDirectory
                .parentDirectory
                .appending(
                    components: Constants.DerivedDirectory.dependenciesDerivedDirectory,
                    moduleName,
                    "\(moduleName).modulemap"
                )
        } else {
            generatedModuleMapPath = packageDirectory.appending(
                components: Constants.DerivedDirectory.name, "\(moduleName).modulemap"
            )
        }

        if FileHandler.shared.exists(umbrellaHeaderPath) {
            if let customModuleMapPath {
                return .custom(customModuleMapPath, umbrellaHeaderPath: umbrellaHeaderPath)
            }
            let moduleMapContent = """
            framework module \(sanitizedModuleName) {
              umbrella header "\(umbrellaHeaderPath.pathString)"

              export *
              module * { export * }
            }
            """
            try FileHandler.shared.write(moduleMapContent, path: generatedModuleMapPath, atomically: true)
            // If 'PublicHeadersDir/ModuleName.h' exists, then use it as the umbrella header.
            return .header(moduleMapPath: generatedModuleMapPath)
        } else if FileHandler.shared.exists(nestedUmbrellaHeaderPath) {
            if let customModuleMapPath {
                return .custom(customModuleMapPath, umbrellaHeaderPath: nestedUmbrellaHeaderPath)
            }
            // If 'PublicHeadersDir/ModuleName/ModuleName.h' exists, then use it as the umbrella header.
            return .nestedHeader
        } else if let customModuleMapPath {
            // User defined modulemap exists, use it
            return .custom(customModuleMapPath, umbrellaHeaderPath: nil)
        } else if FileHandler.shared.exists(publicHeadersPath) {
            // Consider the public headers folder as umbrella directory
            let generatedModuleMapContent =
                """
                module \(sanitizedModuleName) {
                    umbrella "\(publicHeadersPath.pathString)"
                    export *
                }
                """
            try FileHandler.shared.write(generatedModuleMapContent, path: generatedModuleMapPath, atomically: true)
            return .directory(moduleMapPath: generatedModuleMapPath, umbrellaDirectory: publicHeadersPath)
        } else {
            return .none
        }
    }

    static func customModuleMapPath(publicHeadersPath: AbsolutePath) throws -> AbsolutePath? {
        guard FileHandler.shared.exists(publicHeadersPath) else { return nil }

        let moduleMapPath = try RelativePath(validating: ModuleMap.filename)
        let publicHeadersFolderContent = try FileHandler.shared.contentsOfDirectory(publicHeadersPath)

        if publicHeadersFolderContent.contains(publicHeadersPath.appending(moduleMapPath)) {
            return publicHeadersPath.appending(moduleMapPath)
        } else if publicHeadersFolderContent.count == 1,
                  let nestedHeadersPath = publicHeadersFolderContent.first,
                  FileHandler.shared.isFolder(nestedHeadersPath),
                  FileHandler.shared.exists(nestedHeadersPath.appending(moduleMapPath))
        {
            return nestedHeadersPath.appending(moduleMapPath)
        } else {
            return nil
        }
    }
}
