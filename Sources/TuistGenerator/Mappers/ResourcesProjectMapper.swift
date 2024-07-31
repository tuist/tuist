import Foundation
import Path
import TuistCore
import TuistSupport
import XcodeGraph

/// A project mapper that adds support for defining resources in targets that don't support it
public class ResourcesProjectMapper: ProjectMapping { // swiftlint:disable:this type_body_length
    private let contentHasher: ContentHashing
    public init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        guard !project.options.disableBundleAccessors else {
            return (project, [])
        }
        logger.debug("Transforming project \(project.name): Generating bundles for libraries'")

        var sideEffects: [SideEffectDescriptor] = []
        var targets: [String: Target] = [:]

        for target in project.targets.values {
            let (mappedTargets, targetSideEffects) = try mapTarget(target, project: project)
            mappedTargets.forEach { targets[$0.name] = $0 }
            sideEffects.append(contentsOf: targetSideEffects)
        }

        var project = project
        project.targets = targets

        return (project, sideEffects)
    }

    // swiftlint:disable:next function_body_length
    public func mapTarget(_ target: Target, project: Project) throws -> ([Target], [SideEffectDescriptor]) {
        if target.resources.resources.isEmpty, target.coreDataModels.isEmpty { return ([target], []) }

        var additionalTargets: [Target] = []
        var sideEffects: [SideEffectDescriptor] = []

        let sanitizedTargetName = target.name.sanitizedModuleName
        let bundleName = "\(project.name)_\(sanitizedTargetName)"
        var modifiedTarget = target

        if !target.supportsResources {
            let resourcesTarget = Target(
                name: bundleName,
                destinations: target.destinations,
                product: .bundle,
                productName: bundleName,
                bundleId: "\(target.bundleId).resources",
                deploymentTargets: target.deploymentTargets,
                infoPlist: .extendingDefault(with: [:]),
                settings: Settings(
                    base: [
                        "CODE_SIGNING_ALLOWED": "NO",
                    ],
                    configurations: [:]
                ),
                resources: target.resources,
                copyFiles: target.copyFiles,
                coreDataModels: target.coreDataModels,
                filesGroup: target.filesGroup
            )
            modifiedTarget.resources.resources = []
            modifiedTarget.copyFiles = []
            modifiedTarget.dependencies.append(.target(name: bundleName, condition: .when(target.dependencyPlatformFilters)))
            additionalTargets.append(resourcesTarget)
        }

        if target.supportsSources,
           target.sources.containsSwiftFiles
        {
            let (filePath, data) = synthesizedSwiftFile(bundleName: bundleName, target: target, project: project)

            let hash = try data.map(contentHasher.hash)
            let sourceFile = SourceFile(path: filePath, contentHash: hash)
            let sideEffect = SideEffectDescriptor.file(.init(path: filePath, contents: data, state: .present))
            modifiedTarget.sources.append(sourceFile)
            sideEffects.append(sideEffect)
        }

        if project.isExternal,
           target.supportsSources,
           target.sources.containsObjcFiles,
           target.resources.containsBundleAccessedResources,
           !target.supportsResources
        {
            let (headerFilePath, headerData) = synthesizedObjcHeaderFile(bundleName: bundleName, target: target, project: project)

            let headerHash = try headerData.map(contentHasher.hash)
            let headerFile = SourceFile(path: headerFilePath, contentHash: headerHash)
            let headerSideEffect = SideEffectDescriptor.file(.init(path: headerFilePath, contents: headerData, state: .present))

            let gccPrefixHeader = "$(SRCROOT)/\(headerFile.path.relative(to: project.path).pathString)"
            var settings = modifiedTarget.settings?.base ?? SettingsDictionary()
            settings["GCC_PREFIX_HEADER"] = .string(gccPrefixHeader)
            modifiedTarget.settings = modifiedTarget.settings?.with(base: settings)

            sideEffects.append(headerSideEffect)

            let (resourceAccessorPath, resourceAccessorData) = synthesizedObjcImplementationFile(
                bundleName: bundleName,
                target: target,
                project: project
            )
            modifiedTarget.sources.append(
                SourceFile(
                    path: resourceAccessorPath,
                    contentHash: try resourceAccessorData.map(contentHasher.hash)
                )
            )
            sideEffects.append(
                SideEffectDescriptor.file(
                    FileDescriptor(
                        path: resourceAccessorPath,
                        contents: resourceAccessorData,
                        state: .present
                    )
                )
            )
        }

        return ([modifiedTarget] + additionalTargets, sideEffects)
    }

    func synthesizedSwiftFile(bundleName: String, target: Target, project: Project) -> (AbsolutePath, Data?) {
        let filePath = project.derivedDirectoryPath(for: target)
            .appending(component: Constants.DerivedDirectory.sources)
            .appending(component: "TuistBundle+\(target.name.toValidSwiftIdentifier()).swift")

        let content: String = ResourcesProjectMapper.fileContent(
            targetName: target.name,
            bundleName: bundleName,
            target: target,
            in: project
        )
        return (filePath, content.data(using: .utf8))
    }

    private func synthesizedObjcHeaderFile(bundleName _: String, target: Target, project: Project) -> (AbsolutePath, Data?) {
        let filePath = synthesizedFilePath(target: target, project: project, fileExtension: "h")

        let content: String = ResourcesProjectMapper.objcHeaderFileContent(targetName: target.name)
        return (filePath, content.data(using: .utf8))
    }

    private func synthesizedObjcImplementationFile(
        bundleName: String,
        target: Target,
        project: Project
    ) -> (AbsolutePath, Data?) {
        let filePath = synthesizedFilePath(target: target, project: project, fileExtension: "m")

        let content: String = ResourcesProjectMapper.objcImplementationFileContent(
            targetName: target.name,
            bundleName: bundleName
        )
        return (filePath, content.data(using: .utf8))
    }

    private func synthesizedFilePath(target: Target, project: Project, fileExtension: String) -> AbsolutePath {
        let filename = "TuistBundle+\(target.name.uppercasingFirst).\(fileExtension)"
        return project.derivedDirectoryPath(for: target).appending(components: Constants.DerivedDirectory.sources, filename)
    }

    // swiftlint:disable:next function_body_length
    static func fileContent(targetName _: String, bundleName: String, target: Target, in project: Project) -> String {
        var content = """
        // swiftlint:disable all
        // swift-format-ignore-file
        // swiftformat:disable all
        import Foundation
        """
        if !target.supportsResources {
            content += swiftSPMBundleAccessorString(for: target, and: bundleName)
        } else {
            content += swiftFrameworkBundleAccessorString(for: target)
        }

        // Add public accessors only for non external projects
        if !project.isExternal, !target.sourcesContainsPublicResourceClassName {
            content += publicBundleAccessorString(for: target)
        }

        content += """
        // swiftlint:enable all
        // swiftformat:enable all
        """
        return content
    }

    static func objcHeaderFileContent(
        targetName: String
    ) -> String {
        return """
        #import <Foundation/Foundation.h>

        #if __cplusplus
        extern "C" {
        #endif

        NSBundle* \(targetName)_SWIFTPM_MODULE_BUNDLE(void);

        #define SWIFTPM_MODULE_BUNDLE \(targetName)_SWIFTPM_MODULE_BUNDLE()

        #if __cplusplus
        }
        #endif
        """
    }

    static func objcImplementationFileContent(
        targetName: String,
        bundleName: String
    ) -> String {
        return """
        #import <Foundation/Foundation.h>
        #import "TuistBundle+\(targetName).h"

        NSBundle* \(targetName)_SWIFTPM_MODULE_BUNDLE(void) {
            NSURL *bundleURL = [[[NSBundle mainBundle] bundleURL] URLByAppendingPathComponent:@"\(bundleName).bundle"];

            NSBundle *bundle = [NSBundle bundleWithURL:bundleURL];

            return bundle;
        }
        """
    }

    private static func publicBundleAccessorString(for target: Target) -> String {
        """
        // MARK: - Objective-C Bundle Accessor
        @objc
        public class \(target.productName.toValidSwiftIdentifier())Resources: NSObject {
        @objc public class var bundle: Bundle {
            return .module
        }
        }
        """
    }

    private static func swiftSPMBundleAccessorString(for target: Target, and bundleName: String) -> String {
        """
        // MARK: - Swift Bundle Accessor - for SPM
        private class BundleFinder {}
        extension Foundation.Bundle {
        /// Since \(target.name) is a \(
            target
                .product
        ), the bundle containing the resources is copied into the final product.
        static let module: Bundle = {
            let bundleName = "\(bundleName)"
            var candidates = [
                Bundle.main.resourceURL,
                Bundle(for: BundleFinder.self).resourceURL,
                Bundle.main.bundleURL,
            ]
            // This is a fix to make Previews work with bundled resources.
            // Logic here is taken from SPM's generated `resource_bundle_accessors.swift` file,
            // which is located under the derived data directory after building the project.
            if let override = ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_PATH"] {
                candidates.append(URL(fileURLWithPath: override))
                // Deleting derived data and not rebuilding the frameworks containing resources may result in a state
                // where the bundles are only available in the framework's directory that is actively being previewed.
                // Since we don't know which framework this is, we also need to look in all the framework subpaths.
                if let subpaths = try? FileManager.default.contentsOfDirectory(atPath: override) {
                    for subpath in subpaths {
                        if subpath.hasSuffix(".framework") {
                            candidates.append(URL(fileURLWithPath: override + "/" + subpath))
                        }
                    }
                }
            }
            for candidate in candidates {
                let bundlePath = candidate?.appendingPathComponent(bundleName + ".bundle")
                if let bundle = bundlePath.flatMap(Bundle.init(url:)) {
                    return bundle
                }
            }
            fatalError("unable to find bundle named \(bundleName)")
        }()
        }
        """
    }

    private static func swiftFrameworkBundleAccessorString(for target: Target) -> String {
        """
        // MARK: - Swift Bundle Accessor for Frameworks
        private class BundleFinder {}
        extension Foundation.Bundle {
        /// Since \(target.name) is a \(
            target
                .product
        ), the bundle for classes within this module can be used directly.
        static let module = Bundle(for: BundleFinder.self)
        }
        """
    }
}

extension [SourceFile] {
    fileprivate var containsObjcFiles: Bool {
        contains(where: { $0.path.extension == "m" || $0.path.extension == "mm" })
    }

    fileprivate var containsSwiftFiles: Bool {
        contains(where: { $0.path.extension == "swift" })
    }
}

extension ResourceFileElements {
    fileprivate var containsBundleAccessedResources: Bool {
        !resources.filter { $0.path.extension != "xcprivacy" }.isEmpty
    }
}

extension Target {
    fileprivate var sourcesContainsPublicResourceClassName: Bool {
        sources.contains(where: { $0.path.basename == "\(name)Resources.swift" })
    }
}
