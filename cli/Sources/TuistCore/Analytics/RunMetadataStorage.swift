import FileSystem
import Foundation
import Path
import TuistEnvironment
import TuistLogging
import TuistSupport
import XcodeGraph

public struct AnalyticsCommandMetadata: Equatable, Sendable {
    public let name: String
    public let subcommand: String?
    public let commandArguments: [String]

    public init(
        name: String,
        subcommand: String?,
        commandArguments: [String]
    ) {
        self.name = name
        self.subcommand = subcommand
        self.commandArguments = commandArguments
    }
}

/// Storage for run metadata, such as binary cache.
public actor RunMetadataStorage {
    @TaskLocal public static var current: RunMetadataStorage = .init()

    private let fileSystem: FileSysteming

    public init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    /// A unique ID associated with a specific run
    public var runId: String {
        Environment.current.processId
    }

    /// Graph associated with the current run
    public private(set) var graph: Graph?
    public func update(graph: Graph?) {
        self.graph = graph
    }

    /// Graph associated with the current run
    public private(set) var graphBinaryBuildDuration: TimeInterval?
    public func update(graphBinaryBuildDuration: TimeInterval?) {
        self.graphBinaryBuildDuration = graphBinaryBuildDuration
    }

    /// Binar cache-specific cache items
    public private(set) var binaryCacheItems: [AbsolutePath: [String: CacheItem]] = [:]
    public func update(binaryCacheItems: [AbsolutePath: [String: CacheItem]]) {
        self.binaryCacheItems = binaryCacheItems
    }

    /// Selective testing-specific cache items
    public private(set) var selectiveTestingCacheItems: [AbsolutePath: [String: CacheItem]] = [:]
    public func update(selectiveTestingCacheItems: [AbsolutePath: [String: CacheItem]]) {
        self.selectiveTestingCacheItems = selectiveTestingCacheItems
    }

    /// Target content hash subhashes keyed by hash. Multiple graph mappers (binary cache, selective
    /// testing, cache warm) each contribute their own entries, so updates merge into the existing
    /// dictionary rather than replacing it.
    public private(set) var targetContentHashSubhashes: [String: TargetContentHashSubhashes] = [:]
    public func update(targetContentHashSubhashes: [String: TargetContentHashSubhashes]) {
        self.targetContentHashSubhashes.merge(targetContentHashSubhashes, uniquingKeysWith: { _, new in new })
    }

    /// Preview associated with the current run
    public private(set) var previewId: String?
    public func update(previewId: String?) {
        self.previewId = previewId
    }

    /// Path to the result bundle that should be uploaded when running commands like `tuist xcodebuild test`.
    /// Leave `nil` to signal that no result bundle should be uploaded (e.g. when `--inspect-mode local` processes it locally).
    public private(set) var resultBundlePath: AbsolutePath?
    public func update(resultBundlePath: AbsolutePath?) {
        self.resultBundlePath = resultBundlePath
    }

    /// The ID of the latest build run.
    public private(set) var buildRunId: String?
    public func update(buildRunId: String?) {
        self.buildRunId = buildRunId
    }

    /// The ID of the latest test run.
    public private(set) var testRunId: String?
    public func update(testRunId: String?) {
        self.testRunId = testRunId
    }

    /// The generate command event's id, minted client-side. `tuist generate` sends it as the command
    /// event id (so the server stores the graph under it) and persists it; a later local Xcode build
    /// references it so the build page can resolve the generation's graph for its Module Cache breakdown.
    public private(set) var generationId: String?
    public func update(generationId: String?) {
        self.generationId = generationId
    }

    /// The URL of the uploaded build run.
    public private(set) var buildRunURL: URL?
    public func update(buildRunURL: URL?) {
        self.buildRunURL = buildRunURL
    }

    /// Cache endpoint used for the current run (regional module cache)
    public private(set) var cacheEndpoint: String = ""
    public func update(cacheEndpoint: String) {
        self.cacheEndpoint = cacheEndpoint
    }

    /// Per-scheme test run summaries captured locally, used to render the GitHub Actions job
    /// summary without waiting for the server to finish processing the uploaded result bundle.
    public private(set) var testRunReports: [RunReportTestRun] = []
    public func add(testRunReport: RunReportTestRun) {
        testRunReports.append(testRunReport)
    }

    /// Per-scheme build run summaries captured locally, used to render the GitHub Actions job
    /// summary without waiting for the server to finish processing the uploaded activity log.
    public private(set) var buildRunReports: [RunReportBuildRun] = []
    public func add(buildRunReport: RunReportBuildRun) {
        buildRunReports.append(buildRunReport)
    }

    /// Canonical command metadata derived during command execution.
    public private(set) var resolvedCommandMetadata: AnalyticsCommandMetadata?
    public func update(resolvedCommandMetadata: AnalyticsCommandMetadata?) {
        self.resolvedCommandMetadata = resolvedCommandMetadata
    }

    /// Writes a `RunMetadata` snapshot of the current storage to the `.xctestproducts`
    /// bundle at `testProductsPath`. Used by the build phase of the split build/test
    /// topology (`tuist test --build-only`) so the test phase can restore the same
    /// analytics state when it runs as a separate process.
    ///
    /// Failures are logged as warnings; persistence is best-effort and never blocks the
    /// caller's run.
    public func writeMetadata(to testProductsPath: AbsolutePath) async {
        let runMetadata = RunMetadata(
            graph: graph,
            binaryCacheItems: binaryCacheItems,
            selectiveTestingCacheItems: selectiveTestingCacheItems,
            targetContentHashSubhashes: targetContentHashSubhashes,
            buildRunId: buildRunId
        )
        let runMetadataPath = testProductsPath.appending(component: RunMetadata.fileName)
        do {
            try await fileSystem.writeAsJSON(runMetadata, at: runMetadataPath)
        } catch {
            Logger.current.warning("Failed to persist run metadata: \(error.localizedDescription)")
        }
    }

    /// Restores run metadata from a `RunMetadata` JSON file previously written to the
    /// `.xctestproducts` bundle at `testProductsPath`. Used by the test phase of the split
    /// build/test topology (`tuist test --without-building -testProductsPath …`).
    ///
    /// No-op when the file is absent (bundles produced by older Tuist versions). Failures
    /// are logged as warnings and never block the caller's run.
    public func restoreMetadata(from testProductsPath: AbsolutePath) async {
        let runMetadataPath = testProductsPath.appending(component: RunMetadata.fileName)
        guard (try? await fileSystem.exists(runMetadataPath)) == true else { return }
        do {
            let runMetadata: RunMetadata = try await fileSystem.readJSONFile(at: runMetadataPath)
            if let graph = runMetadata.graph {
                update(graph: graph)
            }
            if !runMetadata.binaryCacheItems.isEmpty {
                update(binaryCacheItems: runMetadata.binaryCacheItems)
            }
            if !runMetadata.selectiveTestingCacheItems.isEmpty {
                update(selectiveTestingCacheItems: runMetadata.selectiveTestingCacheItems)
            }
            if !runMetadata.targetContentHashSubhashes.isEmpty {
                update(targetContentHashSubhashes: runMetadata.targetContentHashSubhashes)
            }
            if let buildRunId = runMetadata.buildRunId {
                update(buildRunId: buildRunId)
            }
        } catch {
            Logger.current.warning("Failed to restore run metadata: \(error.localizedDescription)")
        }
    }
}
