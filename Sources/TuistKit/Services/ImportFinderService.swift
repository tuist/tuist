import Foundation
import Path
import ProjectAutomation
import Tools
import TuistCore
import TuistLoader
import TuistSupport
import XcodeGraph

enum ImportFinderServiceError: FatalError, Equatable {
    case targetNotFound(target: String)

    var description: String {
        switch self {
        case let .targetNotFound(target):
            "Target \(target) was not found"
        }
    }

    var type: ErrorType {
        switch self {
        case .targetNotFound:
            .abort
        }
    }
}

final class ImportFinderService {
    private let manifestGraphLoader: ManifestGraphLoading

    convenience init() {
        let manifestLoader = ManifestLoaderFactory()
            .createManifestLoader()
        let manifestGraphLoader = ManifestGraphLoader(
            manifestLoader: manifestLoader,
            workspaceMapper: SequentialWorkspaceMapper(mappers: []),
            graphMapper: SequentialGraphMapper([])
        )
        self.init(
            manifestGraphLoader: manifestGraphLoader
        )
    }

    init(manifestGraphLoader: ManifestGraphLoading) {
        self.manifestGraphLoader = manifestGraphLoader
    }

    func run(
        path: AbsolutePath,
        targetName: String
    ) async throws {
        let (graph, _, _) = try await manifestGraphLoader.load(path: path)
        let target = graph
            .projects
            .map(\.value.targets)
            .flatMap { $0 }
            .map(\.value)
            .filter { $0.name == targetName }
            .first
        guard let target else { throw ImportFinderServiceError.targetNotFound(target: targetName) }
        let imports = Set(await handleTarget(target: target))
        print("Used imports: \n\(imports.joined(separator: ", "))")
    }

    func handleTarget(target: XcodeGraph.Target) async -> [String] {
        return await withTaskGroup(of: [String].self) { [weak self] group in
            var imports = [String]()
            guard let self else { return [] }
            for file in target.sources {
                group.addTask {
                    return await self.matchPattern(at: file)
                }
            }
            for await entity in group {
                imports.append(contentsOf: entity)
            }
            return imports
        }
    }

    private func matchPattern(at source: SourceFile) async -> [String] {
        var language: ProgrammingLanguage
        switch source.path.url.pathExtension {
        case "swift":
            language = .swift
        case "objc":
            language = .objc
        default:
            return []
        }

        guard let sourceCode = try? String(contentsOf: source.path.url) else {
            return []
        }

        do {
            return try ImportSourceCodeScanner().extractImports(
                from: sourceCode,
                language: language
            )
        } catch {
            return []
        }
    }
}
