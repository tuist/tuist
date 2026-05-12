import Foundation
import Path
import TuistCore
import TuistLogging
import TuistSupport
import XcodeGraph

/// Generates the plumbing that lets targets without a runtime bundle reach their resources via
/// `Bundle.module` — mirroring SwiftPM's shape.
///
/// For each target the mapper, when needed:
///   1. Splits the target's buildable folders and resources between the target itself and a
///      synthesised companion `.bundle` target (for static frameworks and other targets that
///      cannot host their own resources).
///   2. Writes a `TuistBundle+<Target>.swift` accessor into the target's Derived directory so
///      that user code can call `Bundle.module`.
///   3. For external Obj-C targets, also emits SwiftPM-shaped C bridging files.
public struct ResourcesProjectMapper: ProjectMapping {
    private let contentHasher: ContentHashing
    private let buildableFolderChecker: BuildableFolderChecking
    private let partitioner = BuildableFolderResourcePartitioner()

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

    public func mapTarget(_ target: Target, project: Project) async throws -> ([Target], [SideEffectDescriptor]) {
        guard try await targetNeedsBundleSynthesis(target, project: project) else {
            return ([target], [])
        }

        let bundleName = "\(project.name)_\(target.name.sanitizedModuleName)"
        var modifiedTarget = target
        var additionalTargets: [Target] = []
        var sideEffects: [SideEffectDescriptor] = []

        if targetNeedsCompanionBundle(target) {
            let companion = synthesizeCompanionBundle(for: target, project: project, bundleName: bundleName)
            modifiedTarget = companion.modifiedTarget
            additionalTargets.append(companion.bundleTarget)
        }

        if try await targetNeedsSwiftAccessor(target) {
            try appendSwiftBundleAccessor(
                to: &modifiedTarget,
                sideEffects: &sideEffects,
                target: target,
                project: project,
                bundleName: bundleName
            )
        }

        if targetNeedsObjcAccessor(target, project: project) {
            try appendObjcBundleAccessor(
                to: &modifiedTarget,
                sideEffects: &sideEffects,
                target: target,
                project: project,
                bundleName: bundleName
            )
        }

        return ([modifiedTarget] + additionalTargets, sideEffects)
    }

    // MARK: - Should we map this target?

    private func targetNeedsBundleSynthesis(_ target: Target, project: Project) async throws -> Bool {
        if !target.resources.resources.isEmpty { return true }
        if !target.coreDataModels.isEmpty { return true }
        if target.sources.contains(where: { $0.path.extension == "metal" }) { return true }
        if try await buildableFolderChecker.containsResources(target.buildableFolders) { return true }
        if buildableFoldersContainSynthesizedFiles(target: target, project: project) { return true }
        if buildableFoldersContainMetalFiles(target.buildableFolders) { return true }
        return false
    }

    private func targetNeedsCompanionBundle(_ target: Target) -> Bool {
        !target.supportsResources || target.product == .staticFramework
    }

    private func targetNeedsSwiftAccessor(_ target: Target) async throws -> Bool {
        let containsSwift = target.sources.contains(where: { $0.path.extension == "swift" })
        let containsSourcesInBuildableFolders = try await buildableFolderChecker
            .containsSources(target.buildableFolders)
        return containsSwift || containsSourcesInBuildableFolders
    }

    private func targetNeedsObjcAccessor(_ target: Target, project: Project) -> Bool {
        guard case .external = project.type else { return false }
        let containsObjc = target.sources.contains {
            $0.path.extension == "m" || $0.path.extension == "mm"
        }
        let hasBundleResources = !target.resources.resources
            .filter { $0.path.extension != "xcprivacy" }
            .isEmpty
        let needsBundle = !target.supportsResources || target.product == .staticFramework
        return containsObjc && hasBundleResources && needsBundle
    }

    private func buildableFoldersContainSynthesizedFiles(target: Target, project: Project) -> Bool {
        let extensions = Set(project.resourceSynthesizers.flatMap(\.extensions))
        return target.buildableFolders.contains(where: { folder in
            folder.resolvedFiles.contains(where: { extensions.contains($0.path.extension ?? "") })
        })
    }

    /// Xcode compiles `.metal` sources into a `default.metallib` resource. For static frameworks
    /// and other targets that can't host their own resources, the metallib must live in the
    /// companion bundle so `Bundle.module.makeDefaultLibrary(...)` can find it.
    private func buildableFoldersContainMetalFiles(_ folders: [BuildableFolder]) -> Bool {
        folders.contains(where: { folder in
            folder.resolvedFiles.contains(where: { $0.path.extension == "metal" })
        })
    }

    // MARK: - Companion bundle target

    private struct CompanionBundleResult {
        let modifiedTarget: Target
        let bundleTarget: Target
    }

    private func synthesizeCompanionBundle(
        for target: Target,
        project: Project,
        bundleName: String
    ) -> CompanionBundleResult {
        let partition = partitioner.partition(target.buildableFolders)

        let bundleTarget = makeBundleTarget(
            for: target,
            bundleName: bundleName,
            buildableFolders: partition.bundleTargetFolders
        )

        var modifiedTarget = target

        // Source files: keep everything except `.metal` (which Xcode compiles into a resource
        // that must live in the companion bundle alongside the buildable-folder partition).
        modifiedTarget.sources = target.sources.filter { $0.path.extension != "metal" }

        // Asset catalogs (.xcassets) sit on the main target's Sources phase so Xcode generates
        // typed asset symbols, and on the companion bundle's Resources phase so the catalog is
        // actually compiled. Mirrors SwiftPM's PIF builder:
        //   - https://github.com/swiftlang/swift-package-manager/blob/main/Sources/XCBuildSupport/PIFBuilder.swift#L944-L952
        //   - https://github.com/swiftlang/swift-package-manager/blob/main/Sources/SwiftBuildSupport/PackagePIFProjectBuilder.swift#L347-L353
        for resource in target.resources.resources where resource.path.extension == "xcassets" {
            modifiedTarget.sources.append(SourceFile(path: resource.path))
        }

        // String catalogs (.xcstrings) stay on the main target's Resources phase so Xcode runs
        // localization extraction and stale-string detection in the same target where the Swift
        // sources live. They are also kept on the companion bundle's Resources phase so the
        // catalog is compiled to .strings for `Bundle.module` lookups at runtime.
        // `PACKAGE_RESOURCE_BUNDLE_NAME` (set on the main target below) makes swift-build's
        // `XCStringsCompiler.shouldCompileCatalog` skip catalog compilation here, so the catalog
        // is only compiled once, inside the companion bundle.
        //   - https://github.com/swiftlang/swift-build/blob/main/Sources/SWBApplePlatform/XCStringsCompiler.swift
        var explicitResources = partition.originalTargetExplicitResources
        explicitResources.append(
            contentsOf: target.resources.resources.filter { $0.path.extension == "xcstrings" }
        )
        modifiedTarget.resources.resources = explicitResources
        modifiedTarget.copyFiles = []
        modifiedTarget.buildableFolders = partition.originalTargetFolders
        modifiedTarget.dependencies.append(.target(
            name: bundleName,
            status: .required,
            condition: .when(target.dependencyPlatformFilters)
        ))

        // `PACKAGE_RESOURCE_BUNDLE_NAME` tells Xcode that a companion bundle target owns the
        // compiled asset catalogs, which suppresses `LinkAssetCatalog` on this target while
        // preserving `GenerateAssetSymbols` for typed resource accessors. Without this,
        // `xcodebuild archive` fails for static targets because `LinkAssetCatalog` references an
        // `UninstalledProducts` path that doesn't exist during archiving.
        //
        // `PACKAGE_RESOURCE_TARGET_KIND = "regular"` tells Xcode this is a normal compilation
        // target (not a resource bundle) so string extraction runs here where the Swift source
        // references live. Mirrors SwiftPM's PIF builder:
        //   - https://github.com/swiftlang/swift-package-manager/blob/main/Sources/XCBuildSupport/PIFBuilder.swift#L642
        //   - https://github.com/swiftlang/swift-package-manager/blob/main/Sources/SwiftBuildSupport/PackagePIFProjectBuilder%2BModules.swift#L524
        var base = modifiedTarget.settings?.base ?? SettingsDictionary()
        base["PACKAGE_RESOURCE_BUNDLE_NAME"] = .string(bundleName)
        base["PACKAGE_RESOURCE_TARGET_KIND"] = .string("regular")
        modifiedTarget.settings = modifiedTarget.settings?.with(base: base)
            ?? Settings(base: base, configurations: [:])

        return CompanionBundleResult(modifiedTarget: modifiedTarget, bundleTarget: bundleTarget)
    }

    private func makeBundleTarget(
        for target: Target,
        bundleName: String,
        buildableFolders: [BuildableFolder]
    ) -> Target {
        var synthesizedMetadata = target.metadata
        synthesizedMetadata.tags.insert("tuist:synthesized")
        return Target(
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
            buildableFolders: buildableFolders
        )
    }

    // MARK: - Synthesised accessor files

    private func appendSwiftBundleAccessor(
        to modifiedTarget: inout Target,
        sideEffects: inout [SideEffectDescriptor],
        target: Target,
        project: Project,
        bundleName: String
    ) throws {
        let file = BundleAccessorTemplate.swiftAccessor(target: target, bundleName: bundleName, project: project)
        let hash = try file.contents.map(contentHasher.hash)
        modifiedTarget.sources.append(SourceFile(path: file.path, contentHash: hash))
        sideEffects.append(.file(.init(path: file.path, contents: file.contents, state: .present)))
    }

    private func appendObjcBundleAccessor(
        to modifiedTarget: inout Target,
        sideEffects: inout [SideEffectDescriptor],
        target: Target,
        project: Project,
        bundleName: String
    ) throws {
        let header = BundleAccessorTemplate.objcAccessorHeader(target: target, project: project)
        let implementation = BundleAccessorTemplate.objcAccessorImplementation(
            target: target,
            bundleName: bundleName,
            project: project
        )

        // Point the target's prefix header at the synthesised .h so every Obj-C file picks up
        // `SWIFTPM_MODULE_BUNDLE` without an explicit `#import`.
        let prefixHeaderPath = "$(SRCROOT)/\(header.path.relative(to: project.path).pathString)"
        var settings = modifiedTarget.settings?.base ?? SettingsDictionary()
        settings["GCC_PREFIX_HEADER"] = .string(prefixHeaderPath)
        modifiedTarget.settings = modifiedTarget.settings?.with(base: settings)

        let implementationHash = try implementation.contents.map(contentHasher.hash)
        modifiedTarget.sources.append(SourceFile(path: implementation.path, contentHash: implementationHash))

        sideEffects.append(.file(.init(path: header.path, contents: header.contents, state: .present)))
        sideEffects.append(.file(.init(path: implementation.path, contents: implementation.contents, state: .present)))
    }
}
