import Path
import XcodeGraph

/// Result of splitting a target's buildable folders between the main target and the companion
/// resource bundle generated for static frameworks / targets that cannot host their own resources.
///
/// Xcode treats a buildable folder as a single synchronized group. To attach the same folder to
/// both targets, we duplicate the folder reference and add complementary exclusion rules to each
/// copy: the main-target copy excludes bundle-only resources, and the bundle-target copy
/// excludes source files. Discovered catalogs retain membership in both targets; explicit
/// catalog declarations take precedence over synchronized membership.
struct BuildableFolderResourcePartition {
    /// Folders (or per-folder views) that stay on the original target.
    var originalTargetFolders: [BuildableFolder] = []

    /// Folders (or per-folder views) that move to the companion resource bundle.
    var bundleTargetFolders: [BuildableFolder] = []
}

struct BuildableFolderResourcePartitioner {
    func partition(
        _ folders: [BuildableFolder],
        explicitCatalogSources: Set<AbsolutePath> = [],
        explicitCatalogResources: Set<AbsolutePath> = []
    ) -> BuildableFolderResourcePartition {
        var partition = folders.reduce(into: BuildableFolderResourcePartition()) { result, folder in
            switch folder.partitioned() {
            case .none:
                result.originalTargetFolders.append(folder)
            case let .some(partition):
                if let original = partition.originalTargetFolder {
                    result.originalTargetFolders.append(original)
                }
                if let bundle = partition.bundleTargetFolder {
                    result.bundleTargetFolders.append(bundle)
                }
            }
        }
        // Explicit entries own their per-file metadata. Exclude their implicit membership rather
        // than dropping tags, conditions or compiler flags while deduplicating the build phases.
        let originalExplicitCatalogs = explicitCatalogSources.union(explicitCatalogResources)
        partition.originalTargetFolders = partition.originalTargetFolders.map {
            $0.excludingExplicitCatalogs(originalExplicitCatalogs)
        }
        partition.bundleTargetFolders = partition.bundleTargetFolders.map {
            $0.excludingExplicitCatalogs(explicitCatalogResources)
        }
        return partition
    }
}

// MARK: - Single-folder partition

private struct SingleFolderPartition {
    let originalTargetFolder: BuildableFolder?
    let bundleTargetFolder: BuildableFolder?
}

extension BuildableFolder {
    fileprivate func excludingExplicitCatalogs(_ paths: Set<AbsolutePath>) -> BuildableFolder {
        guard !paths.isEmpty else { return self }
        let excluded = resolvedFiles.filter { paths.contains($0.path) }.map(\.path)
        guard !excluded.isEmpty else { return self }
        return BuildableFolder(
            path: path,
            exceptions: exceptions.addingExcluded(paths: excluded),
            resolvedFiles: resolvedFiles.filter { !paths.contains($0.path) }
        )
    }

    fileprivate func partitioned() -> SingleFolderPartition? {
        if let folderLevel = folderLevelPartition() {
            return folderLevel
        }

        let split = splitFilesByRouting()
        let bundleEntries = split.bundleOnly + split.shared

        if bundleEntries.isEmpty {
            return ambivalentFolderPartition()
        }

        if split.originalOnly.isEmpty, split.shared.isEmpty {
            return SingleFolderPartition(
                originalTargetFolder: nil,
                bundleTargetFolder: self
            )
        }

        return duplicateWithExclusions(
            originalEntries: split.originalOnly,
            bundleEntries: split.bundleOnly,
            sharedEntries: split.shared
        )
    }

    /// When the folder name itself signals a pure-resource folder (e.g. `Foo.xcassets`), route
    /// the whole folder to the bundle without inspecting its contents.
    private func folderLevelPartition() -> SingleFolderPartition? {
        guard path.isResourceLike, !path.isSourceLike, resolvedFiles.isEmpty else { return nil }
        return SingleFolderPartition(
            originalTargetFolder: nil,
            bundleTargetFolder: self
        )
    }

    /// When the folder contains no bundle-bound files, keep it on the original target. The
    /// duplicate-on-original branch only fires for folder names that look both source-like and
    /// resource-like (rare), where we still want to materialise the folder explicitly.
    private func ambivalentFolderPartition() -> SingleFolderPartition? {
        guard path.isResourceLike, path.isSourceLike else { return nil }
        return SingleFolderPartition(
            originalTargetFolder: self,
            bundleTargetFolder: nil
        )
    }

    private func splitFilesByRouting() -> (
        originalOnly: [BuildableFolderFile],
        shared: [BuildableFolderFile],
        bundleOnly: [BuildableFolderFile]
    ) {
        var originalOnly: [BuildableFolderFile] = []
        var shared: [BuildableFolderFile] = []
        var bundleOnly: [BuildableFolderFile] = []
        for file in resolvedFiles {
            switch FilePartitionRouting(file.path) {
            case .originalTargetOnly:
                originalOnly.append(file)
            case .sharedBetweenTargets:
                shared.append(file)
            case .bundleTargetOnly:
                bundleOnly.append(file)
            }
        }
        return (originalOnly, shared, bundleOnly)
    }

    private func duplicateWithExclusions(
        originalEntries: [BuildableFolderFile],
        bundleEntries: [BuildableFolderFile],
        sharedEntries: [BuildableFolderFile]
    ) -> SingleFolderPartition {
        let original = BuildableFolder(
            path: path,
            exceptions: exceptions.addingExcluded(paths: bundleEntries.map(\.path)),
            resolvedFiles: originalEntries + sharedEntries
        )
        let bundle = BuildableFolder(
            path: path,
            exceptions: exceptions.addingExcluded(paths: originalEntries.map(\.path)),
            resolvedFiles: bundleEntries + sharedEntries
        )
        return SingleFolderPartition(
            originalTargetFolder: original,
            bundleTargetFolder: bundle
        )
    }
}

// MARK: - Per-file routing rules

/// Where a single file inside a buildable folder ends up when the target needs a companion
/// resource bundle. Mirrors SwiftPM's classification (see references below): most files are
/// either pure sources or pure resources. Catalogs stay in both targets' synchronized-folder
/// membership. swift-build moves source-generating Resources entries into Sources for asset
/// and string symbol generation (when their respective generation settings are enabled).
/// The companion bundle compiles both catalogs for runtime access; PACKAGE_RESOURCE_BUNDLE_NAME
/// suppresses compilation on the main target. Swift string extraction is independently gated
/// by SWIFT_EMIT_LOC_STRINGS, not catalog membership.
///
/// SwiftPM additionally shares `.xcdatamodeld`, `.xcdatamodel`, `.mlmodel` and `.mlpackage`
/// for code generation. Tuist handles `.xcdatamodeld` via `target.coreDataModels`.
///
/// References:
/// - https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageLoading/TargetSourcesBuilder.swift#L811-L865
/// - https://github.com/swiftlang/swift-package-manager/blob/main/Sources/SwiftBuildSupport/PackagePIFProjectBuilder.swift#L274-L362
private enum FilePartitionRouting {
    /// File that compiles on the original target only — Swift, Obj-C, C, headers, …
    case originalTargetOnly
    /// Catalog that participates in main-target symbol generation and companion-bundle compilation.
    case sharedBetweenTargets
    /// File whose compiled output Xcode packages into the bundle — pure resources plus the
    /// SwiftPM-style "source-y resources" via `AbsolutePath.routesThroughResourceBundle`.
    case bundleTargetOnly

    init(_ path: AbsolutePath) {
        if ["xcassets", "xcstrings"].contains(path.extension?.lowercased() ?? "") {
            self = .sharedBetweenTargets
        } else if path.routesThroughResourceBundle {
            self = .bundleTargetOnly
        } else if path.isSourceLike {
            self = .originalTargetOnly
        } else {
            self = .bundleTargetOnly
        }
    }
}

// MARK: - Path predicates

extension AbsolutePath {
    /// True for extensions Tuist's domain model treats as sources (`Target.validSourceExtensions`)
    /// but SwiftPM treats as resources (`xcbuildFileTypes`). They must ride on the resource
    /// bundle target so Xcode compiles them in the bundle's context — today only `.metal`,
    /// whose `default.metallib` output has to live next to `Bundle.module`.
    var routesThroughResourceBundle: Bool {
        `extension`?.lowercased() == "metal"
    }

    fileprivate var isSourceLike: Bool {
        guard let ext = `extension` else { return false }
        let valid = Target.validSourceExtensions
            + Target.validSourceCompatibleFolderExtensions
            + Target.validHeaderExtensions
        return valid.contains { $0.caseInsensitiveCompare(ext) == .orderedSame }
    }

    fileprivate var isResourceLike: Bool {
        guard let ext = `extension` else { return false }
        let valid = Target.validResourceExtensions + Target.validResourceCompatibleFolderExtensions
        return valid.contains { $0.caseInsensitiveCompare(ext) == .orderedSame }
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
