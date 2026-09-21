import FileSystem
import Foundation
import Path
import TuistConstants
import TuistThreadSafe

public enum ManifestLookupExcludes {
    /// Glob patterns that prune `Derived/FrameworkSearchPaths` from lookups over a project tree.
    ///
    /// The directory holds one symbolic link per precompiled framework, pointing into the binary cache. Nothing a
    /// manifest declares lives there, and following those links descends into every cached framework tree, which on
    /// large graphs dominates the time spent loading them. `FileSysteming.glob(directory:include:exclude:)` evaluates
    /// `exclude` before `include`, so the pattern prunes descent at the directory boundary rather than filtering after
    /// the walk.
    public static let frameworkSearchPathLinks = [
        "**/\(Constants.DerivedDirectory.name)/\(Constants.DerivedDirectory.frameworkSearchPaths)",
    ]
}

/// Accumulates how long manifest glob expansions take while it is bound to ``current``.
///
/// Logging each expansion would add a line per pattern per target, which on a large workspace buries the lines that
/// matter, and no single duration threshold separates one slow pattern from many moderately slow ones. The summary
/// reports the cumulative time and the slowest expansions instead, which stays a handful of lines at any size.
public final class ManifestGlobDurations: Sendable {
    @TaskLocal public static var current: ManifestGlobDurations?

    private struct Expansion {
        let pattern: String
        let duration: TimeInterval
    }

    private struct State {
        var count = 0
        var totalDuration: TimeInterval = 0
        var slowest: [Expansion] = []
    }

    private let slowestLimit: Int
    private let state = ThreadSafe(State())

    public init(slowestLimit: Int = 10) {
        self.slowestLimit = slowestLimit
    }

    func record(pattern: String, duration: TimeInterval) {
        state.mutate { state in
            state.count += 1
            state.totalDuration += duration
            guard state.slowest.count < slowestLimit || duration > (state.slowest.last?.duration ?? 0) else { return }
            let index = state.slowest.firstIndex(where: { $0.duration < duration }) ?? state.slowest.endIndex
            state.slowest.insert(Expansion(pattern: pattern, duration: duration), at: index)
            if state.slowest.count > slowestLimit { state.slowest.removeLast() }
        }
    }

    /// A summary of the recorded expansions, or `nil` when there were none. Durations overlap because expansions run
    /// concurrently, so the total can exceed the wall-clock time of the phase that ran them.
    public func summary() -> String? {
        state.withValue { state in
            guard state.count > 0 else { return nil }
            let slowest = state.slowest
                .map { "  \(Self.format($0.duration)) \($0.pattern)" }
                .joined(separator: "\n")
            return """
            Manifest globs: \(state.count) expansions took \(Self.format(state.totalDuration)) in total. Slowest:
            \(slowest)
            """
        }
    }

    private static func format(_ duration: TimeInterval) -> String {
        String(format: "%.3fs", duration)
    }
}

extension FileSysteming {
    /// Expands glob patterns declared in a manifest (sources, resources, files, buildable folders, …) without descending
    /// into `Derived/FrameworkSearchPaths`. See ``ManifestLookupExcludes/frameworkSearchPathLinks``.
    ///
    /// While a ``ManifestGlobDurations`` is bound, the time each expansion takes to complete is recorded in it.
    public func manifestGlob(
        directory: Path.AbsolutePath,
        include: [String]
    ) throws -> AnyThrowingAsyncSequenceable<AbsolutePath> {
        let paths = try glob(directory: directory, include: include, exclude: ManifestLookupExcludes.frameworkSearchPathLinks)
        guard let durations = ManifestGlobDurations.current else { return paths }

        let pattern = include
            .map { directory.pathString.hasSuffix("/") ? directory.pathString + $0 : directory.pathString + "/" + $0 }
            .joined(separator: ", ")
        return AsyncThrowingStream<AbsolutePath, Error> { continuation in
            let task = Task {
                let startedAt = DispatchTime.now().uptimeNanoseconds
                defer {
                    let duration = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000_000
                    durations.record(pattern: pattern, duration: duration)
                }
                do {
                    for try await path in paths {
                        continuation.yield(path)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        .eraseToAnyThrowingAsyncSequenceable()
    }

    /// Returns the list of paths that match the given glob pattern, if the directory exists.
    ///
    /// - Parameters:
    ///   - directory: Base absolute directory that glob patterns are relative to.
    ///   - include: A list of glob patterns.
    /// - Throws: an error if the directory where the first glob pattern is declared doesn't exist
    /// - Returns: An async sequence to get the results.
    public func throwingGlob(
        directory: Path.AbsolutePath,
        include: [String]
    ) async throws -> AnyThrowingAsyncSequenceable<AbsolutePath> {
        for include in include {
            try await validateGlobPattern(for: directory, include: include)
        }

        return try manifestGlob(directory: directory, include: include)
    }

    private func validateGlobPattern(
        for directory: AbsolutePath,
        include: String
    ) async throws {
        let globPath = directory.appending(try RelativePath(validating: include)).pathString

        if globPath.isGlobComponent {
            let pathUpToLastNonGlob = try AbsolutePath(validating: globPath).upToLastNonGlob

            if try await !exists(pathUpToLastNonGlob, isDirectory: true) {
                let invalidGlob = InvalidGlob(
                    pattern: globPath,
                    nonExistentPath: pathUpToLastNonGlob
                )
                throw GlobError.nonExistentDirectory(invalidGlob)
            }
        }
    }
}
