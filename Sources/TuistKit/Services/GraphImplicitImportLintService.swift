import Foundation
import Path
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

final class GraphImplicitImportLintService {
    private let graph: Graph

    init(graph: Graph) {
        self.graph = graph
    }

    func lint() async throws {
        let allTargets = graph
            .projects
            .map(\.value.targets)
            .flatMap { $0 }
            .map(\.value)

        let allTargetNames = Set(allTargets.map(\.name))
        print("The following implicit imports have been detected through static code analysis:")
        for target in allTargets {
            let allImports = Set(try await handleTarget(target: target))
            let targetImports = allImports.filter { allTargetNames.contains($0) }
            guard !targetImports.isEmpty else { continue }
            print("Target \(target.name) imports: \(targetImports.joined(separator: ", "))")
        }
    }

    func handleTarget(target: XcodeGraph.Target) async throws -> [String] {
        return try await withThrowingTaskGroup(of: [String].self) { [weak self] group in
            var imports = [String]()
            guard let self else { return [] }
            for file in target.sources {
                group.addTask {
                    return try await self.matchPattern(at: file)
                }
            }
            for try await entity in group {
                imports.append(contentsOf: entity)
            }
            return imports
        }
    }

    private func matchPattern(at source: SourceFile) async throws -> [String] {
        var language: ProgrammingLanguage
        switch source.path.url.pathExtension {
        case "swift":
            language = .swift
        case "h", "m", "cpp", "mm":
            language = .objc
        default:
            return []
        }

        let sourceCode = try String(contentsOf: source.path.url)

        return try ImportSourceCodeScanner().extractImports(
            from: sourceCode,
            language: language
        )
    }
}
