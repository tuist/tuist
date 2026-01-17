import Foundation
import Path
import TuistCore
import TuistSupport
import XcodeGraph

/// A project mapper that adds support for defining resources in targets that don't support it
public class ResourcesProjectMapper: ProjectMapping { // swiftlint:disable:this type_body_length
    private let contentHasher: ContentHashing
    private let buildableFolderChecker: BuildableFolderChecking

    public init(contentHasher: ContentHashing, buildableFolderChecker: BuildableFolderChecking = BuildableFolderChecker()) {
        self.contentHasher = contentHasher
        self.buildableFolderChecker = buildableFolderChecker
    }

    public func map(project: Project) async throws -> (Project, [SideEffectDescriptor]) {
        guard !project.options.disableBundleAccessors else {
            return (project, [])
        }
        Logger.current.debug("Transforming project \(project.name): Generating bundles for libraries'")

        var sideEffects: [SideEffectDescriptor] = []
        var targets: [String: Target] = [:]

        for target in project.targets.values {
            let (mappedTargets, targetSideEffects) = try await mapTarget(target, project: project)
            mappedTargets.forEach { targets[$0.name] = $0 }
            sideEffects.append(contentsOf: targetSideEffects)
        }

        var project = project
        project.targets = targets

        return (project, sideEffects)
    }

    // swiftlint:disable:next function_body_length
    public func mapTarget(_ target: Target, project: Project) async throws -> ([Target], [SideEffectDescriptor]) {
        let containsResourcesInBuildableFolders = try await buildableFolderChecker.containsResources(target.buildableFolders)
        let containsSynthesizedResourcesInBuildableFolders = containsSynthesizedFilesInBuildableFolders(
            target: target,
            project: project
        )
        let supportsResources = target.supportsResources
        if target.resources.resources.isEmpty, target.coreDataModels.isEmpty,
           !target.sources.contains(where: { $0.path.extension == "metal" }),
           !containsResourcesInBuildableFolders,
           !containsSynthesizedResourcesInBuildableFolders
        { return (
            [target],
            []
        ) }

        var additionalTargets: [Target] = []
        var sideEffects: [SideEffectDescriptor] = []

        let sanitizedTargetName = target.name.sanitizedModuleName
        let bundleName = "\(project.name)_\(sanitizedTargetName)"
        var modifiedTarget = target

        let shouldGenerateResourceBundle = !supportsResources &&
            !(project.type == .local && target.product == .staticFramework)

        if shouldGenerateResourceBundle {
            // Keep resources in a separate bundle to match SwiftPM's Bundle.module expectations and avoid collisions.
            let (resourceBuildableFolders, remainingBuildableFolders) = partitionBuildableFoldersForResources(
                target.buildableFolders
            )
            var synthesizedMetadata = target.metadata
            synthesizedMetadata.tags.insert("tuist:synthesized")
            let resourcesTarget = Target(
                name: bundleName,
                destinations: target.destinations,
                product: .bundle,
                productName: bundleName,
                bundleId: "\(target.bundleId).generated.resources",
                deploymentTargets: target.deploymentTargets,
                infoPlist: .extendingDefault(with: [:]),
                settings: Settings(
                    base: [
                        "CODE_SIGNING_ALLOWED": "NO",
                        "SKIP_INSTALL": "YES",
                        "GENERATE_MASTER_OBJECT_FILE": "NO",
                        "VERSIONING_SYSTEM": "",
                    ],
                    configurations: [:]
                ),
                sources: target.sources.filter { $0.path.extension == "metal" },
                resources: target.resources,
                copyFiles: target.copyFiles,
                coreDataModels: target.coreDataModels,
                filesGroup: target.filesGroup,
                metadata: synthesizedMetadata,
                buildableFolders: resourceBuildableFolders
            )
            modifiedTarget.sources = target.sources.filter { $0.path.extension != "metal" }
            modifiedTarget.resources.resources = []
            modifiedTarget.copyFiles = []
            modifiedTarget.buildableFolders = remainingBuildableFolders
            modifiedTarget.dependencies.append(.target(
                name: bundleName,
                status: .required,
                condition: .when(target.dependencyPlatformFilters)
            ))
            additionalTargets.append(resourcesTarget)
        }

        let containSourcesInBuildableFolders = try await buildableFolderChecker.containsSources(target.buildableFolders)
        if target.sources.containsSwiftFiles || containSourcesInBuildableFolders {
            let (filePath, data) = synthesizedSwiftFile(
                bundleName: bundleName,
                target: target,
                project: project,
                supportsResources: supportsResources
            )

            let hash = try data.map(contentHasher.hash)
            let sourceFile = SourceFile(path: filePath, contentHash: hash)
            let sideEffect = SideEffectDescriptor.file(.init(path: filePath, contents: data, state: .present))
            modifiedTarget.sources.append(sourceFile)
            sideEffects.append(sideEffect)
        }

        if case .external = project.type,
           target.sources.containsObjcFiles,
           target.resources.containsBundleAccessedResources || containsResourcesInBuildableFolders
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

    private func containsSynthesizedFilesInBuildableFolders(target: Target, project: Project) -> Bool {
        let extensions = Set(project.resourceSynthesizers.flatMap(\.extensions))
        return target.buildableFolders.contains(where: { folder in
            folder.resolvedFiles.contains(where: { extensions.contains($0.path.extension ?? "") })
        })
    }

    private func synthesizedSwiftFile(
        bundleName: String,
        target: Target,
        project: Project,
        supportsResources: Bool
    ) -> (AbsolutePath, Data?) {
        let filePath = project.derivedDirectoryPath(for: target)
            .appending(component: Constants.DerivedDirectory.sources)
            .appending(component: "TuistBundle+\(target.name.toValidSwiftIdentifier()).swift")

        let content: String = ResourcesProjectMapper.fileContent(
            targetName: target.name,
            bundleName: bundleName,
            target: target,
            in: project,
            supportsResources: supportsResources
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

    /// Splits the incoming buildable folders into two sets:
    ///  - folders that should stay on the original target (sources or mixed folders after excluding resources)
    ///  - folders that should move to the generated bundle (pure resources, or the resource portion of mixed folders)
    /// Mixed folders are duplicated with exclusion rules so the static target keeps sources while the bundle owns resources.
    private func partitionBuildableFoldersForResources(
        _ folders: [BuildableFolder]
    ) -> (resourceFolders: [BuildableFolder], remainingFolders: [BuildableFolder]) {
        folders.reduce(into: (resourceFolders: [BuildableFolder](), remainingFolders: [BuildableFolder]())) { result, folder in
            guard let partition = folder.partitionedForResources() else {
                result.remainingFolders.append(folder)
                return
            }

            if let sourcesFolder = partition.sourcesFolder {
                result.remainingFolders.append(sourcesFolder)
            }

            if let resourcesFolder = partition.resourcesFolder {
                result.resourceFolders.append(resourcesFolder)
            }
        }
    }

    // swiftlint:disable:next function_body_length
    static func fileContent(
        targetName _: String,
        bundleName: String,
        target: Target,
        in project: Project,
        supportsResources: Bool
    ) -> String {
        let bundleAccessor = if target.product == .staticFramework {
            swiftStaticFrameworkBundleAccessorString(for: target, bundleName: bundleName)
        } else if supportsResources {
            swiftFrameworkBundleAccessorString(for: target)
        } else {
            swiftSPMBundleAccessorString(for: target, and: bundleName)
        }

        // External projects ship their own public API, so we only mirror SwiftPM's Bundle.module accessors here.
        let (imports, publicBundleAccessor): (String, String) = switch project.type {
        case .external,
             .local where target.sourcesContainsPublicResourceClassName:
            (
                """
                import Foundation
                """,
                ""
            )
        case .local:
            (
                """
                #if hasFeature(InternalImportsByDefault)
                public import Foundation
                #else
                import Foundation
                #endif
                """,
                publicBundleAccessorString(for: target)
            )
        }

        return """
        // periphery:ignore:all
        // swiftlint:disable:this file_name
        // swiftlint:disable all
        // swift-format-ignore-file
        // swiftformat:disable all
        \(imports)
        \(bundleAccessor)
        \(publicBundleAccessor)
        // swiftformat:enable all
        // swiftlint:enable all
        """
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

    /// Mirrors SwiftPM's Objective-C resource bundle accessor shape.
    /// https://github.com/swiftlang/swift-package-manager/blob/main/Sources/Build/BuildDescription/ClangModuleBuildDescription.swift
    static func objcImplementationFileContent(
        targetName: String,
        bundleName: String
    ) -> String {
        return """
        #import <Foundation/Foundation.h>
        #import "TuistBundle+\(targetName).h"

        @interface \(targetName)BundleFinder : NSObject
        @end

        @implementation \(targetName)BundleFinder
        @end

        NSBundle* \(targetName)_SWIFTPM_MODULE_BUNDLE(void) {
            NSString *bundleName = @"\(bundleName)";

            NSURL *bundleURL = [[NSBundle bundleForClass:\(targetName)BundleFinder.self] resourceURL];
            NSMutableArray *candidates = [NSMutableArray arrayWithObjects:
                                          [[NSBundle mainBundle] resourceURL],
                                          bundleURL,
                                          [[NSBundle mainBundle] bundleURL],
                                          nil];

            NSString* override = [[[NSProcessInfo processInfo] environment] objectForKey:@"PACKAGE_RESOURCE_BUNDLE_PATH"];
            if (override) {
                [candidates addObject:override];

                NSString *subpaths = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:override error:nil];
                if (subpaths) {
                    for (NSString *subpath in subpaths) {
                        if ([subpath hasSuffix:@".framework"]) {
                            [candidates addObject:[NSURL fileURLWithPath:[NSString stringWithFormat:@"%@/%@", override, subpath]]];
                        }
                    }
                }
            }

            #if __has_include(<XCTest/XCTest.h>)
            [candidates addObject:[bundleURL URLByAppendingPathComponent:@".."]];
            #endif

            for (NSURL *candidate in candidates) {
                NSURL *bundlePath = [candidate URLByAppendingPathComponent:[NSString stringWithFormat:@"%@%@", bundleName, @".bundle"]];
                NSBundle *bundle = [NSBundle bundleWithURL:bundlePath];

                if (bundle) {
                    return bundle;
                }
            }

            [NSException raise:@"BundleNotFound" format:nil];
        }
        """
    }

    private static func publicBundleAccessorString(for target: Target) -> String {
        """
        // MARK: - Objective-C Bundle Accessor
        @objc
        public final class \(target.productName.toValidSwiftIdentifier())Resources: NSObject {
        @objc public class var bundle: Bundle {
            return .module
        }
        }
        """
    }

    /// Mirrors SwiftPM's generated resource bundle accessor with Tuist-specific search paths.
    /// https://github.com/swiftlang/swift-package-manager/blob/main/Sources/Build/BuildDescription/SwiftModuleBuildDescription.swift
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
                let hostBundle = Bundle(for: BundleFinder.self)
                var candidates = [
                    hostBundle.privateFrameworksURL,
                    hostBundle.bundleURL.appendingPathComponent("Frameworks"),
                    hostBundle.bundleURL,
                    hostBundle.resourceURL,
                    Bundle.main.privateFrameworksURL,
                    Bundle.main.bundleURL.appendingPathComponent("Frameworks"),
                    Bundle.main.bundleURL,
                    Bundle.main.resourceURL,
                ]
                // This is a fix to make Previews work with bundled resources.
                // Logic here is taken from SPM's generated `resource_bundle_accessors.swift` file,
                // which is located under the derived data directory after building the project.
                if let override = ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_PATH"] {
                    candidates.append(URL(fileURLWithPath: override))
                    // Deleting derived data and not rebuilding the frameworks containing resources may result in a state
                    // where the bundles are only available in the framework's directory that is actively being previewed.
                    // Since we don't know which framework this is, we also need to look in all the framework subpaths.
                    if let subpaths = try? Foundation.FileManager.default.contentsOfDirectory(atPath: override) {
                        for subpath in subpaths {
                            if subpath.hasSuffix(".framework") {
                                candidates.append(URL(fileURLWithPath: override + "/" + subpath))
                            }
                        }
                    }
                }

                // This is a fix to make unit tests work with bundled resources.
                // Making this change allows unit tests to search one directory up for a bundle.
                // More context can be found in this PR: https://github.com/tuist/tuist/pull/6895
                if ProcessInfo.processInfo.processName == "xctest"
                    || ProcessInfo.processInfo.processName == "swift-testing"
                {
                    candidates.append(hostBundle.bundleURL.appendingPathComponent(".."))
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

    /// Adapted from SwiftPM's resource bundle accessor logic to handle static frameworks.
    /// https://github.com/swiftlang/swift-package-manager/blob/main/Sources/Build/BuildDescription/SwiftModuleBuildDescription.swift
    private static func swiftStaticFrameworkBundleAccessorString(for target: Target, bundleName: String) -> String {
        """
        // MARK: - Swift Bundle Accessor for Static Frameworks
        extension Foundation.Bundle {
        /// Since \(target.name) is a \(target
            .product), a cut down framework is embedded, with all the resources but only a stub Mach-O image.
            static let module: Bundle = {
                class BundleFinder {}
                let hostBundle = Bundle(for: BundleFinder.self)
                var candidates: [URL?] = [
                    hostBundle.privateFrameworksURL,
                    hostBundle.bundleURL.appendingPathComponent("Frameworks"),
                    hostBundle.bundleURL,
                    hostBundle.bundleURL.deletingLastPathComponent(),
                    hostBundle.resourceURL,
                    Bundle.main.privateFrameworksURL,
                    Bundle.main.bundleURL.appendingPathComponent("Frameworks"),
                    Bundle.main.bundleURL,
                    Bundle.main.resourceURL,
                ].map({ $0?.appendingPathComponent("\(target.productNameWithExtension)") })

                for candidate in candidates {
                    if let bundle = candidate.flatMap(Bundle.init(url:)) {
                        return bundle
                    }
                }

                var bundleCandidates: [URL?] = [
                    hostBundle.resourceURL,
                    hostBundle.bundleURL,
                    hostBundle.privateFrameworksURL,
                    hostBundle.bundleURL.appendingPathComponent("Frameworks"),
                    hostBundle.bundleURL.deletingLastPathComponent(),
                    Bundle.main.resourceURL,
                    Bundle.main.bundleURL,
                    Bundle.main.privateFrameworksURL,
                    Bundle.main.bundleURL.appendingPathComponent("Frameworks"),
                ]
                if ProcessInfo.processInfo.processName == "xctest"
                    || ProcessInfo.processInfo.processName == "swift-testing"
                {
                    bundleCandidates.append(hostBundle.bundleURL.appendingPathComponent(".."))
                }

                for candidate in bundleCandidates {
                    let bundlePath = candidate?.appendingPathComponent("\(bundleName).bundle")
                    if let bundle = bundlePath.flatMap(Bundle.init(url:)) {
                        return bundle
                    }
                }

                return Bundle.main
            }()
        }
        """
    }
}

/// Represents the result of splitting a buildable folder into source and resource subsets.
private struct BuildableFolderPartition {
    /// The view of the folder that should stay on the original target (sources/mixed minus resources).
    let sourcesFolder: BuildableFolder?

    /// The view of the folder that should move to the generated bundle target (resources only).
    let resourcesFolder: BuildableFolder?
}

extension BuildableFolder {
    /// Produces copies of the buildable folder suitable for source-only and resource-only targets.
    /// - Returns: `nil` when the folder should stay untouched on the original target, otherwise a partition describing the two
    /// views.
    fileprivate func partitionedForResources() -> BuildableFolderPartition? {
        if let directAssignment = folderOnlyPartition() {
            return directAssignment
        }

        let (sourceEntries, resourceEntries) = splitFilesByKind()

        if resourceEntries.isEmpty {
            return handleSourceOnlyFolder()
        }

        if sourceEntries.isEmpty {
            return BuildableFolderPartition(
                sourcesFolder: nil,
                resourcesFolder: self
            )
        }

        return duplicateFolderWithExclusions(
            sourceEntries: sourceEntries,
            resourceEntries: resourceEntries
        )
    }

    /// Handles cases where the folder path itself reveals a pure resource folder.
    private func folderOnlyPartition() -> BuildableFolderPartition? {
        // Xcode treats buildable folders as a single synchronized group. To attach the same folder to
        // multiple targets we duplicate the reference and add complementary exclusion rules to each copy.
        if path.isResourceLike, !path.isSourceLike, resolvedFiles.isEmpty {
            return BuildableFolderPartition(sourcesFolder: nil, resourcesFolder: self)
        }
        return nil
    }

    /// Splits the folder contents into source-like and resource-like entries.
    private func splitFilesByKind() -> (sources: [BuildableFolderFile], resources: [BuildableFolderFile]) {
        let sources = resolvedFiles.filter(\.path.isSourceLike)
        let resources = resolvedFiles.filter { !$0.path.isSourceLike }
        return (sources, resources)
    }

    /// Retains the folder on the original target when no resources were found, duplicating it only when both
    /// source and resource heuristics match at the folder level.
    private func handleSourceOnlyFolder() -> BuildableFolderPartition? {
        if path.isResourceLike, path.isSourceLike {
            return BuildableFolderPartition(
                sourcesFolder: BuildableFolder(
                    path: path,
                    exceptions: exceptions,
                    resolvedFiles: resolvedFiles
                ),
                resourcesFolder: nil
            )
        }
        return nil
    }

    /// Duplicates the folder reference and adds complementary exclusions to the source and resource views.
    private func duplicateFolderWithExclusions(
        sourceEntries: [BuildableFolderFile],
        resourceEntries: [BuildableFolderFile]
    ) -> BuildableFolderPartition {
        let sourceExcludedPaths = resourceEntries.map(\.path)
        let resourceExcludedPaths = sourceEntries.map(\.path)

        let sourcesFolder = BuildableFolder(
            path: path,
            exceptions: exceptions.addingExcluded(paths: sourceExcludedPaths),
            resolvedFiles: sourceEntries
        )

        let resourcesFolder = BuildableFolder(
            path: path,
            exceptions: exceptions.addingExcluded(paths: resourceExcludedPaths),
            resolvedFiles: resourceEntries
        )

        return BuildableFolderPartition(
            sourcesFolder: sourcesFolder,
            resourcesFolder: resourcesFolder
        )
    }
}

extension AbsolutePath {
    private func matchesExtension(in allowedExtensions: [String]) -> Bool {
        guard let `extension` else { return false }
        return allowedExtensions.contains { $0.caseInsensitiveCompare(`extension`) == .orderedSame }
    }

    fileprivate var isSourceLike: Bool {
        let validExtensions = Target.validSourceExtensions
            + Target.validSourceCompatibleFolderExtensions
            + ["h", "hpp", "hh", "hxx"]
        return matchesExtension(in: validExtensions)
    }

    fileprivate var isResourceLike: Bool {
        let validExtensions = Target.validResourceExtensions
            + Target.validResourceCompatibleFolderExtensions
        return matchesExtension(in: validExtensions)
    }
}

extension BuildableFolderExceptions {
    fileprivate func addingExcluded(paths: [AbsolutePath]) -> BuildableFolderExceptions {
        guard !paths.isEmpty else { return self }
        var updated = exceptions
        updated.append(
            BuildableFolderException(
                excluded: paths,
                compilerFlags: [:],
                publicHeaders: [],
                privateHeaders: []
            )
        )
        return BuildableFolderExceptions(exceptions: updated)
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
