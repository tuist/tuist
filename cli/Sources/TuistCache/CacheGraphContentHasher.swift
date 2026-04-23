import FileSystem
import Foundation
import Mockable
import Path
import TuistCore
import TuistEnvironment
import TuistHasher
import TuistLogging
import TuistSupport
import XcodeGraph

@Mockable
public protocol CacheGraphContentHashing {
    func contentHashes(
        for graph: Graph,
        configuration: String?,
        defaultConfiguration: String?,
        excludedTargets: Set<String>,
        destination: SimulatorDeviceAndRuntime?
    ) async throws -> [GraphTarget: TargetContentHash]
}

public struct CacheGraphContentHasher: CacheGraphContentHashing {
    private let graphContentHasher: GraphContentHashing
    private let contentHasher: ContentHashing
    private let versionFetcher: CacheVersionFetching
    private static let cachableProducts: Set<Product> = [.framework, .staticFramework, .bundle, .macro]
    private static let testableImportPattern = #"(?m)^\s*@testable\s+import\b"#
    private let defaultConfigurationFetcher: DefaultConfigurationFetching
    private let fileSystem: FileSysteming

    public init(
        contentHasher: ContentHashing = ContentHasher()
    ) {
        self.init(
            graphContentHasher: GraphContentHasher(contentHasher: contentHasher),
            contentHasher: contentHasher,
            versionFetcher: CacheVersionFetcher(),
            defaultConfigurationFetcher: DefaultConfigurationFetcher(),
            fileSystem: FileSystem()
        )
    }

    init(
        graphContentHasher: GraphContentHashing,
        contentHasher: ContentHashing,
        versionFetcher: CacheVersionFetching,
        defaultConfigurationFetcher: DefaultConfigurationFetching,
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.graphContentHasher = graphContentHasher
        self.contentHasher = contentHasher
        self.versionFetcher = versionFetcher
        self.defaultConfigurationFetcher = defaultConfigurationFetcher
        self.fileSystem = fileSystem
    }

    public func contentHashes(
        for graph: Graph,
        configuration: String?,
        defaultConfiguration: String?,
        excludedTargets: Set<String>,
        destination: SimulatorDeviceAndRuntime?
    ) async throws -> [GraphTarget: TargetContentHash] {
        if let exportHashedGraphPath = Environment.current.variables["TUIST_EXPORT_HASHED_GRAPH_PATH"],
           let exportPath = try? AbsolutePath(validating: exportHashedGraphPath)
        {
            try await fileSystem.writeAsJSON(graph, at: exportPath)
            Logger.current.debug("Graph used for hashing exported to \(exportPath.pathString)")
        }

        let graphTraverser = GraphTraverser(graph: graph)
        let version = versionFetcher.version()
        let configuration = try defaultConfigurationFetcher.fetch(
            configuration: configuration,
            defaultConfiguration: defaultConfiguration,
            graph: graph
        )
        let testableImportTargets = try await testableImportTargets(
            graphTraverser: graphTraverser,
            excludedTargets: excludedTargets
        )

        let hashes = try await graphContentHasher.contentHashes(
            for: graph,
            include: {
                isGraphTargetHashable(
                    $0,
                    graphTraverser: graphTraverser,
                    excludedTargets: excludedTargets,
                    testableImportTargets: testableImportTargets
                )
            },
            destination: destination,
            additionalStrings: [
                configuration,
                try SwiftVersionProvider.current.swiftlangVersion(),
                version.rawValue,
            ]
        )

        return hashes
    }

    private func isGraphTargetHashable(
        _ target: GraphTarget,
        graphTraverser: GraphTraversing,
        excludedTargets: Set<String>,
        testableImportTargets: Set<GraphTarget>
    ) -> Bool {
        let product = target.target.product
        let name = target.target.name

        // The second condition is to exclude the resources bundle associated to the given target name
        let isExcluded = excludedTargets.contains(name) || excludedTargets
            .contains(target.target.name.dropPrefix("\(target.project.name)_"))
        let dependsOnXCTest = graphTraverser.dependsOnXCTest(path: target.path, name: name)
        let isHashableProduct = CacheGraphContentHasher.cachableProducts.contains(product)
        let containsTestableImports = testableImportTargets.contains(target)

        return isHashableProduct && !isExcluded && !dependsOnXCTest && !containsTestableImports
    }

    private func isMacro(_ target: GraphTarget, graphTraverser: GraphTraversing) -> Bool {
        !graphTraverser.directSwiftMacroExecutables(path: target.path, name: target.target.name).isEmpty
    }

    private func testableImportTargets(
        graphTraverser: GraphTraversing,
        excludedTargets: Set<String>
    ) async throws -> Set<GraphTarget> {
        let candidates = Array(graphTraverser.allTargets().filter { target in
            isHashableCandidate(target, graphTraverser: graphTraverser, excludedTargets: excludedTargets)
        })
        let maxConcurrentTasks = Environment.current.isSwiftFileSystemBackendEnabled ? Int.max : 100
        let matches = try await candidates.concurrentCompactMap(maxConcurrentTasks: maxConcurrentTasks) { target in
            try await containsTestableImports(in: target.target) ? target : nil
        }

        return Set(matches.compactMap { $0 })
    }

    private func isHashableCandidate(
        _ target: GraphTarget,
        graphTraverser: GraphTraversing,
        excludedTargets: Set<String>
    ) -> Bool {
        let product = target.target.product
        let name = target.target.name
        let isExcluded = excludedTargets.contains(name) || excludedTargets
            .contains(target.target.name.dropPrefix("\(target.project.name)_"))
        let dependsOnXCTest = graphTraverser.dependsOnXCTest(path: target.path, name: name)
        let isHashableProduct = CacheGraphContentHasher.cachableProducts.contains(product)

        return isHashableProduct && !isExcluded && !dependsOnXCTest
    }

    private func containsTestableImports(in target: Target) async throws -> Bool {
        let sourceFiles = (target.sources.map(\.path) + target.buildableFolders.flatMap(\.resolvedFiles).map(\.path))
            .filter { $0.extension == "swift" }

        for sourceFile in sourceFiles {
            guard try await fileSystem.exists(sourceFile) else { continue }
            let sourceCode = try await fileSystem.readTextFile(at: sourceFile)
            if sourceCode.range(of: CacheGraphContentHasher.testableImportPattern, options: .regularExpression) != nil {
                return true
            }
        }

        return false
    }
}
