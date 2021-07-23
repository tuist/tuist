import TSCBasic
import TuistSupport

/// Protocol that allows to generate a modulemap for an SPM target.
/// It implements the Swift Package Manager logic
/// [documented here](https://github.com/apple/swift-package-manager/blob/main/Documentation/Usage.md#creating-c-language-targets) and
/// [implemented here](https://github.com/apple/swift-package-manager/blob/main/Sources/PackageLoading/ModuleMapGenerator.swift).
public protocol SwiftPackageManagerModuleMapGenerating {
    func generate(moduleName: String, publicHeadersPath: AbsolutePath) throws -> AbsolutePath?
}

public final class SwiftPackageManagerModuleMapGenerator: SwiftPackageManagerModuleMapGenerating {
    enum ModuleMapType: Equatable    {
        case none
        case custom
        case header(AbsolutePath)
        case directory(AbsolutePath)
    }

    public init() {}

    public func generate(moduleName: String, publicHeadersPath: AbsolutePath) throws -> AbsolutePath? {
        let moduleMapPath = publicHeadersPath.appending(component: "module.modulemap")
        let umbrellaHeaderPath = publicHeadersPath.appending(component: moduleName + ".h")
        let nestedUmbrellaHeaderPath = publicHeadersPath.appending(component: moduleName).appending(component: moduleName + ".h")

        let moduleMapType: ModuleMapType

        if FileHandler.shared.exists(moduleMapPath) {
            // User defined modulemap exists, use it
            moduleMapType = .custom
        } else if FileHandler.shared.exists(umbrellaHeaderPath) {
            // If 'PublicHeadersDir/ModuleName.h' exists, then use it as the umbrella header.
            moduleMapType = .header(umbrellaHeaderPath)
        } else if FileHandler.shared.exists(nestedUmbrellaHeaderPath) {
            // If 'PublicHeadersDir/ModuleName/ModuleName.h' exists, then use it as the umbrella header.
            moduleMapType = .header(nestedUmbrellaHeaderPath)
        } else if FileHandler.shared.exists(publicHeadersPath) {
            // Otherwise, consider the public headers folder as umbrella directory
            moduleMapType = .directory(publicHeadersPath)
        } else {
            moduleMapType = .none
        }

        let generatedModuleMapContent: String
        switch moduleMapType {
        case .none:
            return nil
        case .custom:
            return moduleMapPath
        case .header(let path):
            generatedModuleMapContent =
                """
                module \(moduleName) {
                    umbrella header "\(path.pathString)"
                    export *
                }
                """
        case .directory(let path):
            generatedModuleMapContent =
                """
                module \(moduleName) {
                    umbrella "\(path.pathString)"
                    export *
                }
                """
        }

        let generatedModuleMapPath = publicHeadersPath.appending(component: "\(moduleName).modulemap")
        try FileHandler.shared.write(generatedModuleMapContent, path: generatedModuleMapPath, atomically: true)
        return generatedModuleMapPath
    }
}
