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
/// resource bundle. The mental model mirrors SwiftPM's: source files compile on the original
/// target, resource files (including a handful of extensions that look "source-like" but route
/// through xcbuild's resource pipeline) compile on the bundle, and `.xcstrings` straddles both.
///
/// See `TargetSourcesBuilder` (where SwiftPM declares `xcbuildFileTypes`) and
/// `PackagePIFProjectBuilder.processResources` (where those extensions are emitted to the
/// resource bundle target):
/// - https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageLoading/TargetSourcesBuilder.swift#L811-L865
/// - https://github.com/swiftlang/swift-package-manager/blob/main/Sources/SwiftBuildSupport/PackagePIFProjectBuilder.swift#L274-L362
fileprivate enum FilePartitionRouting {
    /// File that compiles on the original target only — Swift, Obj-C, C, headers, …
    case originalTargetOnly
    /// File that must appear on *both* targets — the original so Xcode runs extraction /
    /// symbol generation with the Swift code, the bundle so `Bundle.module` can resolve the
    /// compiled artifact at runtime. Today: `.xcstrings`.
    case sharedBetweenTargets
    /// File whose compiled output Xcode packages into the bundle — pure resources plus the
    /// SwiftPM-style "source-y resources" (`.metal` → `default.metallib`).
    case bundleTargetOnly

    init(extension fileExtension: String?) {
        let ext = (fileExtension ?? "").lowercased()
        if Self.sharedWithOriginalTarget.contains(ext) {
            self = .sharedBetweenTargets
        } else if Self.routedToBundle.contains(ext) {
            self = .bundleTargetOnly
        } else if AbsolutePath.isSourceLikeExtension(ext) {
            self = .originalTargetOnly
        } else {
            self = .bundleTargetOnly
        }
    }

    /// `.xcstrings` belongs on both targets. `PACKAGE_RESOURCE_BUNDLE_NAME` (set on the main
    /// target) makes swift-build skip the duplicate compile, so Xcode runs extraction on the
    /// main target while only the bundle actually compiles the catalog.
    /// https://github.com/swiftlang/swift-build/blob/main/Sources/SWBApplePlatform/XCStringsCompiler.swift
    private static let sharedWithOriginalTarget: Set<String> = ["xcstrings"]

    /// Extensions SwiftPM declares as `xcbuildFileTypes` (resources processed by xcbuild) that
    /// also happen to be in Tuist's `validSourceExtensions`. Routing them to the bundle matches
    /// SwiftPM's PIF builder, which adds these as source files of the resource bundle target so
    /// the compiled output (e.g. `default.metallib`) lands inside `Bundle.module`.
    static let routedToBundle: Set<String> = ["metal"]
}

// MARK: - Path predicates

extension AbsolutePath {
    /// True for file extensions that SwiftPM routes through the resource bundle even though
    /// Tuist's domain model classifies them as sources (`.metal` today). Used both by the
    /// resource mapper's early-return guard and by the per-file routing in the partitioner.
    var routesThroughResourceBundle: Bool {
        guard let `extension` else { return false }
        return FilePartitionRouting.routedToBundle.contains(`extension`.lowercased())
    }

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
