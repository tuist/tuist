import FileSystem
import Foundation
import Path
import TuistLogging
import TuistSupport

/// Frees the derived data that a cache warm has finished with, while the warm is still running.
///
/// `tuist cache` builds every scheme and destination into one derived data directory and only
/// assembles the XCFrameworks once all of them are done. Nothing removes a destination's output in
/// between, so the command's peak disk usage is the sum of every destination rather than the
/// largest one. On a workspace with hundreds of targets that is tens of gigabytes, and it is what
/// makes the command exhaust an ephemeral CI machine part-way through the last destination — the
/// failure is reported by the compiler as `No space left on device` on whichever object file
/// happened to be open, or, when the build system is the one that hits it first, as an opaque
/// `The Xcode build system has crashed`.
///
/// Reclaiming is safe because the outputs are already consumed by the time it runs: a destination's
/// products are copied into the scratch `artifacts/` tree as soon as its build returns, and its
/// intermediates are of no use to any other destination — each products directory
/// (`Debug-iphonesimulator`, `Debug-iphoneos`, `Debug`, …) gets intermediates of its own. The one
/// exception is a products directory a later scheme of the same warm builds into again, which is
/// why callers pass the reserved set: removing those would buy nothing and cost a rebuild.
public struct CacheWarmBuildOutputReclaimer {
    private let fileSystem: FileSysteming

    public init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    /// Removes the products and intermediates that `productsDirectoryName` produced.
    ///
    /// A no-op when the directory is reserved by a later step of the same warm.
    public func reclaim(
        derivedDataPath: AbsolutePath,
        productsDirectoryName: String,
        reservedProductsDirectoryNames: Set<String>
    ) async {
        guard !reservedProductsDirectoryNames.contains(productsDirectoryName) else { return }

        await remove(derivedDataPath.appending(components: ["Build", "Products", productsDirectoryName]))
        for intermediates in await intermediateDirectories(in: derivedDataPath, for: productsDirectoryName) {
            await remove(intermediates)
        }
    }

    /// Removes the result bundle an `xcodebuild` invocation was given.
    ///
    /// The warm passes `-resultBundlePath` only to keep xcodebuild from writing a bundle next to
    /// the project; nothing reads the bundles back, so one per invocation would otherwise sit in
    /// derived data until the command ends.
    public func reclaimResultBundle(at path: AbsolutePath) async {
        await remove(path)
    }

    /// Every project in the workspace gets its own `<project>.build` directory under
    /// `Intermediates.noindex`, each holding one subdirectory per products directory it built into.
    /// Shared state (`XCBuildData`, precompiled modules) sits beside them and is left alone: it is not
    /// per-destination, and the next destination is about to read it.
    private func intermediateDirectories(
        in derivedDataPath: AbsolutePath,
        for productsDirectoryName: String
    ) async -> [AbsolutePath] {
        let root = derivedDataPath.appending(components: ["Build", "Intermediates.noindex"])
        guard (try? await fileSystem.exists(root, isDirectory: true)) == true else { return [] }
        let projectBuildDirectories = (try? await fileSystem.glob(directory: root, include: ["*.build"]).collect()) ?? []
        return projectBuildDirectories.map { $0.appending(component: productsDirectoryName) }
    }

    /// Reclaiming is an optimization, so a directory that will not go away is logged and ignored:
    /// failing the warm over it would trade a slow build for no build at all, and the scratch
    /// directory is discarded when the command ends regardless.
    private func remove(_ path: AbsolutePath) async {
        guard (try? await fileSystem.exists(path)) == true else { return }
        do {
            try await fileSystem.remove(path)
        } catch {
            Logger.current.debug("Could not reclaim build output at \(path.pathString): \(error)")
        }
    }
}
