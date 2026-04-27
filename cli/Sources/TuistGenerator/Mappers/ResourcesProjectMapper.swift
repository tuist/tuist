import Foundation
import Path
import TuistConstants
import TuistCore
import TuistLogging
import TuistSupport
import XcodeGraph

/// A project mapper that adds support for defining resources in targets that don't support it
public struct ResourcesProjectMapper: ProjectMapping { // swiftlint:disable:this type_body_length
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
        if target.resources.resources.isEmpty, target.coreDataModels.isEmpty,
           !target.sources.contains(where: { $0.path.extension == "metal" }),
           !(try await buildableFolderChecker.containsResources(target.buildableFolders)),
           !containsSynthesizedFilesInBuildableFolders(target: target, project: project)
        { return (
            [target],
            []
        ) }

        var additionalTargets: [Target] = []
        var sideEffects: [SideEffectDescriptor] = []

        let sanitizedTargetName = target.name.sanitizedModuleName
        let bundleName = "\(project.name)_\(sanitizedTargetName)"
        var modifiedTarget = target

        if !target.supportsResources || target.product == .staticFramework {
            let (
                resourceBuildableFolders,
                remainingBuildableFolders,
                originalTargetExplicitResources
            ) = partitionBuildableFoldersForResources(
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
                        // https://github.com/swiftlang/swift-package-manager/blob/main/Sources/XCBuildSupport/PIFBuilder.swift#L925
                        // https://github.com/swiftlang/swift-package-manager/blob/main/Sources/SwiftBuildSupport/PackagePIFProjectBuilder.swift#L225
                        "PACKAGE_RESOURCE_TARGET_KIND": "resource",
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
            // Asset catalogs and string catalogs are added to the main target's Sources build
            // phase so Xcode generates typed symbols. This mirrors SwiftPM's PIF builder:
            //   - https://github.com/swiftlang/swift-package-manager/blob/main/Sources/XCBuildSupport/PIFBuilder.swift#L944-L952
            //   - https://github.com/swiftlang/swift-package-manager/blob/main/Sources/SwiftBuildSupport/PackagePIFProjectBuilder.swift#L345-L360
            // Both are also compiled into the companion resource bundle via its Resources phase.
            // The companion bundle declares PACKAGE_RESOURCE_TARGET_KIND = "resource" (above)
            // so Xcode treats it as a pure resource container and skips string extraction.
            // The main target carries PACKAGE_RESOURCE_TARGET_KIND = "regular" (below) so Xcode
            // runs extraction here where the Swift source references live.
            let codeGeneratingResourceExtensions: Set<String> = ["xcassets", "xcstrings"]
            for resource in target.resources.resources {
                if let ext = resource.path.extension, codeGeneratingResourceExtensions.contains(ext) {
                    modifiedTarget.sources.append(SourceFile(path: resource.path))
                }
            }
            modifiedTarget.resources.resources = originalTargetExplicitResources
            modifiedTarget.copyFiles = []
            modifiedTarget.buildableFolders = remainingBuildableFolders
            modifiedTarget.dependencies.append(.target(
                name: bundleName,
                status: .required,
                condition: .when(target.dependencyPlatformFilters)
            ))
            // PACKAGE_RESOURCE_BUNDLE_NAME tells Xcode that a companion bundle target owns the
            // compiled asset catalogs, which suppresses LinkAssetCatalog on this target while
            // preserving GenerateAssetSymbols for typed resource accessors. Without this,
            // xcodebuild archive fails for static targets because LinkAssetCatalog references
            // an UninstalledProducts path that doesn't exist during archiving.
            //
            // PACKAGE_RESOURCE_TARGET_KIND = "regular" tells Xcode this is a normal compilation
            // target (not a resource bundle) so string extraction runs here where the Swift
            // source references live. This mirrors SwiftPM's PIF builder:
            //   - https://github.com/swiftlang/swift-package-manager/blob/main/Sources/XCBuildSupport/PIFBuilder.swift#L642
            //   - https://github.com/swiftlang/swift-package-manager/blob/main/Sources/SwiftBuildSupport/PackagePIFProjectBuilder%2BModules.swift#L524
            var base = modifiedTarget.settings?.base ?? SettingsDictionary()
            base["PACKAGE_RESOURCE_BUNDLE_NAME"] = .string(bundleName)
            base["PACKAGE_RESOURCE_TARGET_KIND"] = .string("regular")
            modifiedTarget.settings = modifiedTarget.settings?.with(base: base)
                ?? Settings(base: base, configurations: [:])
            additionalTargets.append(resourcesTarget)
        }

        let containSourcesInBuildableFolders = try await buildableFolderChecker.containsSources(target.buildableFolders)
        if target.sources.containsSwiftFiles || containSourcesInBuildableFolders {
            let (filePath, data) = synthesizedSwiftFile(bundleName: bundleName, target: target, project: project)

            let hash = try data.map(contentHasher.hash)
            let sourceFile = SourceFile(path: filePath, contentHash: hash)
            let sideEffect = SideEffectDescriptor.file(.init(path: filePath, contents: data, state: .present))
            modifiedTarget.sources.append(sourceFile)
            sideEffects.append(sideEffect)
        }

        if case .external = project.type,
           target.sources.containsObjcFiles,
           target.resources.containsBundleAccessedResources,
           !target.supportsResources || target.product == .staticFramework
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

    private func synthesizedSwiftFile(bundleName: String, target: Target, project: Project) -> (AbsolutePath, Data?) {
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

    /// Splits the incoming buildable folders into:
    ///  - folders that should stay on the original target (source-only, or mixed folders after excluding bundle-owned files)
    ///  - folders that should move to the generated bundle (pure resources, or the resource portion of mixed folders)
    ///  - explicit resource files that should be added to the original target outside the synchronized group
    /// Mixed folders are duplicated with exclusion rules so the static target keeps sources in the synchronized group, while the
    /// bundle owns the resource view and the original target can still explicitly reference files like `.xcstrings`.
    private func partitionBuildableFoldersForResources(
        _ folders: [BuildableFolder]
    ) -> (
        resourceFolders: [BuildableFolder],
        remainingFolders: [BuildableFolder],
        originalTargetExplicitResources: [ResourceFileElement]
    ) {
        folders.reduce(
            into: (
                resourceFolders: [BuildableFolder](),
                remainingFolders: [BuildableFolder](),
                originalTargetExplicitResources: [ResourceFileElement]()
            )
        ) { result, folder in
            guard let partition = folder.partitionedForResources() else {
                result.remainingFolders.append(folder)
                return
            }

            if let originalTargetFolder = partition.originalTargetFolder {
                result.remainingFolders.append(originalTargetFolder)
            }

            if let resourcesFolder = partition.resourcesFolder {
                result.resourceFolders.append(resourcesFolder)
            }

            result.originalTargetExplicitResources.append(contentsOf: partition.originalTargetExplicitResources)
        }
    }

    // swiftlint:disable:next function_body_length
    static func fileContent(targetName _: String, bundleName: String, target: Target, in project: Project) -> String {
        let bundleAccessor = if target.supportsResources, target.product != .staticFramework {
            swiftFrameworkBundleAccessorString(for: target)
        } else {
            swiftSPMBundleAccessorString(for: target, and: bundleName)
        }

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
        let identifier = targetName.toValidSwiftIdentifier()
        return """
        #import <Foundation/Foundation.h>

        #if __cplusplus
        extern "C" {
        #endif

        NSBundle* \(identifier)_SWIFTPM_MODULE_BUNDLE(void) NS_SWIFT_NONISOLATED;

        #define SWIFTPM_MODULE_BUNDLE \(identifier)_SWIFTPM_MODULE_BUNDLE()

        #if __cplusplus
        }
        #endif
        """
    }

    static func objcImplementationFileContent(
        targetName: String,
        bundleName: String
    ) -> String {
        let identifier = targetName.toValidSwiftIdentifier()
        return """
        #import <Foundation/Foundation.h>
        #import "TuistBundle+\(targetName).h"

        @interface \(identifier)BundleFinder : NSObject
        @end

        @implementation \(identifier)BundleFinder
        @end

        NSBundle* \(identifier)_SWIFTPM_MODULE_BUNDLE(void) {
            NSString *bundleName = @"\(bundleName)";

            NSURL *bundleURL = [[NSBundle bundleForClass:\(identifier)BundleFinder.self] resourceURL];
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
        @objc public nonisolated class var bundle: Bundle {
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
            nonisolated static let module: Bundle = {
                let bundleName = "\(bundleName)"
                let bundleFinderResourceURL = Bundle(for: BundleFinder.self).resourceURL
                var candidates = [
                    Bundle.main.resourceURL,
                    bundleFinderResourceURL,
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
                #if canImport(XCTest)
                candidates.append(bundleFinderResourceURL?.appendingPathComponent(".."))
                #endif

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
            nonisolated static let module = Bundle(for: BundleFinder.self)
        }
        """
    }
}

/// Represents the result of splitting a buildable folder into source and resource subsets.
private struct BuildableFolderPartition {
    /// The view of the folder that should stay on the original target.
    let originalTargetFolder: BuildableFolder?

    /// The view of the folder that should move to the generated bundle target (resources only).
    let resourcesFolder: BuildableFolder?

    /// Files that should be added explicitly to the original target outside the synchronized group.
    let originalTargetExplicitResources: [ResourceFileElement]
}

extension BuildableFolder {
    /// Produces copies of the buildable folder suitable for source-only and resource-only targets.
    /// - Returns: `nil` when the folder should stay untouched on the original target, otherwise a partition describing the two
    /// views.
    fileprivate func partitionedForResources() -> BuildableFolderPartition? {
        if let directAssignment = folderOnlyPartition() {
            return directAssignment
        }

        let (originalOnlyEntries, sharedEntries, resourceOnlyEntries) = splitFilesByKind()
        let originalTargetEntries = originalOnlyEntries
        let resourceEntries = resourceOnlyEntries + sharedEntries
        let originalTargetExplicitResources = sharedEntries.map { ResourceFileElement.file(path: $0.path) }

        if resourceEntries.isEmpty {
            return handleOriginalTargetOnlyFolder()
        }

        if originalTargetEntries.isEmpty {
            return BuildableFolderPartition(
                originalTargetFolder: nil,
                resourcesFolder: self,
                originalTargetExplicitResources: originalTargetExplicitResources
            )
        }

        return duplicateFolderWithExclusions(
            originalOnlyEntries: originalOnlyEntries,
            sharedEntries: sharedEntries,
            resourceOnlyEntries: resourceOnlyEntries,
            originalTargetEntries: originalTargetEntries,
            resourceEntries: resourceEntries,
            originalTargetExplicitResources: originalTargetExplicitResources
        )
    }

    /// Handles cases where the folder path itself reveals a pure resource folder.
    private func folderOnlyPartition() -> BuildableFolderPartition? {
        // Xcode treats buildable folders as a single synchronized group. To attach the same folder to
        // multiple targets we duplicate the reference and add complementary exclusion rules to each copy.
        if path.isResourceLike, !path.isSourceLike, resolvedFiles.isEmpty {
            return BuildableFolderPartition(
                originalTargetFolder: nil,
                resourcesFolder: self,
                originalTargetExplicitResources: []
            )
        }
        return nil
    }

    /// Splits the folder contents into files that belong only on the original target, files that should stay in the bundle but
    /// also be promoted as explicit resources on the original target, and files that belong only in the bundle.
    private func splitFilesByKind() -> (
        originalOnlyEntries: [BuildableFolderFile],
        sharedEntries: [BuildableFolderFile],
        resourceOnlyEntries: [BuildableFolderFile]
    ) {
        let originalOnlyEntries = resolvedFiles.filter(\.path.shouldStayOnlyOnOriginalTargetWhenSplittingResources)
        let sharedEntries = resolvedFiles.filter(\.path.shouldBeSharedAcrossTargetsWhenSplittingResources)
        let resourceOnlyEntries = resolvedFiles.filter {
            !$0.path.shouldStayOnlyOnOriginalTargetWhenSplittingResources
                && !$0.path.shouldBeSharedAcrossTargetsWhenSplittingResources
        }
        return (originalOnlyEntries, sharedEntries, resourceOnlyEntries)
    }

    /// Retains the folder on the original target when no bundle-only resources were found, duplicating it only when both
    /// original-target and bundle heuristics match at the folder level.
    private func handleOriginalTargetOnlyFolder() -> BuildableFolderPartition? {
        if path.isResourceLike, path.isSourceLike {
            return BuildableFolderPartition(
                originalTargetFolder: BuildableFolder(
                    path: path,
                    exceptions: exceptions,
                    resolvedFiles: resolvedFiles
                ),
                resourcesFolder: nil,
                originalTargetExplicitResources: []
            )
        }
        return nil
    }

    /// Duplicates the folder reference and adds complementary exclusions to the source and resource views.
    private func duplicateFolderWithExclusions(
        originalOnlyEntries: [BuildableFolderFile],
        sharedEntries: [BuildableFolderFile],
        resourceOnlyEntries: [BuildableFolderFile],
        originalTargetEntries: [BuildableFolderFile],
        resourceEntries: [BuildableFolderFile],
        originalTargetExplicitResources: [ResourceFileElement]
    ) -> BuildableFolderPartition {
        let sourceExcludedPaths = (resourceOnlyEntries + sharedEntries).map(\.path)
        let resourceExcludedPaths = originalOnlyEntries.map(\.path)

        let originalTargetFolder = BuildableFolder(
            path: path,
            exceptions: exceptions.addingExcluded(paths: sourceExcludedPaths),
            resolvedFiles: originalTargetEntries
        )

        let resourcesFolder = BuildableFolder(
            path: path,
            exceptions: exceptions.addingExcluded(paths: resourceExcludedPaths),
            resolvedFiles: resourceEntries
        )

        return BuildableFolderPartition(
            originalTargetFolder: originalTargetFolder,
            resourcesFolder: resourcesFolder,
            originalTargetExplicitResources: originalTargetExplicitResources
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

    fileprivate var shouldStayOnlyOnOriginalTargetWhenSplittingResources: Bool {
        isSourceLike && !shouldBeSharedAcrossTargetsWhenSplittingResources
    }

    fileprivate var shouldBeSharedAcrossTargetsWhenSplittingResources: Bool {
        matchesExtension(in: ["xcstrings"])
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
