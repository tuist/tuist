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
            switch FilePartitionRouting(extension: file.path.extension) {
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

/// Where a single file inside a buildable folder should end up when the target needs a companion
/// resource bundle. Centralising the per-extension rules here avoids the predicate-chain pattern
/// the partitioner used to spell across half a dozen properties.
private enum FilePartitionRouting {
    /// Source-like file that lives on the original target only (Swift, Obj-C, headers, …).
    case originalTargetOnly
    /// File that must appear on both the original target's Resources phase (so Xcode runs
    /// extraction / stale-string detection where the source references live) and the bundle's
    /// Resources phase (so `Bundle.module` can resolve at runtime). Today: `.xcstrings`.
    case sharedBetweenTargets
    /// Everything else — pure resources, plus source-like extensions that Xcode compiles into a
    /// resource (today: `.metal` → `default.metallib`).
    case bundleTargetOnly

    init(extension fileExtension: String?) {
        let ext = fileExtension ?? ""
        if Self.sharedExtensions.contains(ext) {
            self = .sharedBetweenTargets
        } else if Self.bundleProducingSourceExtensions.contains(ext) {
            self = .bundleTargetOnly
        } else if AbsolutePath.isSourceLikeExtension(ext) {
            self = .originalTargetOnly
        } else {
            self = .bundleTargetOnly
        }
    }

    /// Files that must live in *both* targets so Xcode can extract symbols on one side and
    /// compile resources on the other.
    private static let sharedExtensions: Set<String> = ["xcstrings"]

    /// Source extensions whose output Xcode treats as a resource (compiled into a file the
    /// companion bundle must contain).
    private static let bundleProducingSourceExtensions: Set<String> = ["metal"]
}

// MARK: - Path predicates

extension AbsolutePath {
    fileprivate static func isSourceLikeExtension(_ fileExtension: String) -> Bool {
        let valid = Target.validSourceExtensions
            + Target.validSourceCompatibleFolderExtensions
            + Target.validHeaderExtensions
        return valid.contains { $0.caseInsensitiveCompare(fileExtension) == .orderedSame }
    }

    fileprivate var isSourceLike: Bool {
        guard let `extension` else { return false }
        return AbsolutePath.isSourceLikeExtension(`extension`)
    }

    fileprivate var isResourceLike: Bool {
        guard let `extension` else { return false }
        let valid = Target.validResourceExtensions + Target.validResourceCompatibleFolderExtensions
        return valid.contains { $0.caseInsensitiveCompare(`extension`) == .orderedSame }
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
