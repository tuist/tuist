import Path
import XcodeGraph

/// Result of splitting a target's buildable folders between the main target and the companion
/// resource bundle generated for static frameworks / targets that cannot host their own resources.
///
/// Xcode treats a buildable folder as a single synchronized group. To attach the same folder to
/// both targets, we duplicate the folder reference and add complementary exclusion rules to each
/// copy: the main-target copy excludes the resource files, and the bundle-target copy excludes
/// the source files.
struct BuildableFolderResourcePartition {
    /// Folders (or per-folder views) that stay on the original target.
    var originalTargetFolders: [BuildableFolder] = []

    /// Folders (or per-folder views) that move to the companion resource bundle.
    var bundleTargetFolders: [BuildableFolder] = []

    /// Files that should also appear on the original target's Resources phase, outside the
    /// synchronized group. Used for `.xcstrings` so Xcode runs localization extraction in the
    /// target where the Swift sources live.
    var originalTargetExplicitResources: [ResourceFileElement] = []
}

struct BuildableFolderResourcePartitioner {
    func partition(_ folders: [BuildableFolder]) -> BuildableFolderResourcePartition {
        folders.reduce(into: BuildableFolderResourcePartition()) { result, folder in
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
                result.originalTargetExplicitResources.append(contentsOf: partition.originalTargetExplicitResources)
            }
        }
    }
}

// MARK: - Single-folder partition

private struct SingleFolderPartition {
    let originalTargetFolder: BuildableFolder?
    let bundleTargetFolder: BuildableFolder?
    let originalTargetExplicitResources: [ResourceFileElement]
}

extension BuildableFolder {
    fileprivate func partitioned() -> SingleFolderPartition? {
        if let folderLevel = folderLevelPartition() {
            return folderLevel
        }

        let split = splitFilesByRouting()
        let bundleEntries = split.bundleOnly + split.shared
        let explicitResources = split.shared.map { ResourceFileElement.file(path: $0.path) }

        if bundleEntries.isEmpty {
            return ambivalentFolderPartition()
        }

        if split.originalOnly.isEmpty {
            return SingleFolderPartition(
                originalTargetFolder: nil,
                bundleTargetFolder: self,
                originalTargetExplicitResources: explicitResources
            )
        }

        return duplicateWithExclusions(
            originalEntries: split.originalOnly,
            bundleEntries: bundleEntries,
            originalTargetExplicitResources: explicitResources
        )
    }

    /// When the folder name itself signals a pure-resource folder (e.g. `Foo.xcassets`), route
    /// the whole folder to the bundle without inspecting its contents.
    private func folderLevelPartition() -> SingleFolderPartition? {
        guard path.isResourceLike, !path.isSourceLike, resolvedFiles.isEmpty else { return nil }
        return SingleFolderPartition(
            originalTargetFolder: nil,
            bundleTargetFolder: self,
            originalTargetExplicitResources: []
        )
    }

    /// When the folder contains no bundle-bound files, keep it on the original target. The
    /// duplicate-on-original branch only fires for folder names that look both source-like and
    /// resource-like (rare), where we still want to materialise the folder explicitly.
    private func ambivalentFolderPartition() -> SingleFolderPartition? {
        guard path.isResourceLike, path.isSourceLike else { return nil }
        return SingleFolderPartition(
            originalTargetFolder: self,
            bundleTargetFolder: nil,
            originalTargetExplicitResources: []
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
        originalTargetExplicitResources: [ResourceFileElement]
    ) -> SingleFolderPartition {
        let original = BuildableFolder(
            path: path,
            exceptions: exceptions.addingExcluded(paths: bundleEntries.map(\.path)),
            resolvedFiles: originalEntries
        )
        let bundle = BuildableFolder(
            path: path,
            exceptions: exceptions.addingExcluded(paths: originalEntries.map(\.path)),
            resolvedFiles: bundleEntries
        )
        return SingleFolderPartition(
            originalTargetFolder: original,
            bundleTargetFolder: bundle,
            originalTargetExplicitResources: originalTargetExplicitResources
        )
    }
}

// MARK: - Per-file routing rules

/// Where a single file inside a buildable folder ends up when the target needs a companion
/// resource bundle. Mirrors SwiftPM's classification (see references below): most files are
/// either pure sources or pure resources; `.xcstrings` is the only extension Tuist routes to
/// *both* targets today (it stays on the main target's Resources phase for stale-string
/// detection and lives in the bundle's Resources phase for runtime resolution).
///
/// SwiftPM additionally adds `.xcassets`, `.xcdatamodeld`, `.xcdatamodel`, `.mlmodel` and
/// `.mlpackage` to *both* targets so the main target can run typed-symbol / codegen tasks. For
/// `target.resources` Tuist matches that shape for `.xcassets` (via a separate code path in
/// `synthesizeCompanionBundle`) and `.xcdatamodeld` (via `target.coreDataModels`). The same
/// "shared with main target" treatment for buildable folders is a known gap; see #TODO.
///
/// References:
/// - https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageLoading/TargetSourcesBuilder.swift#L811-L865
/// - https://github.com/swiftlang/swift-package-manager/blob/main/Sources/SwiftBuildSupport/PackagePIFProjectBuilder.swift#L274-L362
fileprivate enum FilePartitionRouting {
    /// File that compiles on the original target only — Swift, Obj-C, C, headers, …
    case originalTargetOnly
    /// File that must appear on *both* targets. Today: `.xcstrings` (main target's Resources
    /// for stale-string detection, bundle's Resources for runtime resolution).
    case sharedBetweenTargets
    /// File whose compiled output Xcode packages into the bundle — pure resources plus the
    /// SwiftPM-style "source-y resources" via `AbsolutePath.routesThroughResourceBundle`.
    case bundleTargetOnly

    init(_ path: AbsolutePath) {
        if path.extension?.lowercased() == "xcstrings" {
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
