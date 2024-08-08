import Foundation
import Path
import Tools
import TuistCore
import TuistGenerator
import TuistLoader
import TuistSupport
import XcodeGraph

final class GraphImplicitImportLintService {
    let importSourceCodeScanner: ImportSourceCodeScanner

    init(importSourceCodeScanner: ImportSourceCodeScanner) {
        self.importSourceCodeScanner = importSourceCodeScanner
    }

    func lint(graph: GraphTraverser) async throws -> [Target: Set<String>] {
        let allTargets = graph
            .allTargets()

        let allTargetNames = Set(allTargets.map(\.target.productName))

        var implicitTargetImports: [Target: Set<String>] = [:]
        for project in graph.projects.values {
            let allTargets = project.targets.values

            for target in allTargets {
                let targetImports = Set(try await imports(for: target))
                let targetTuistDeclaredDependencies = target.dependencies.compactMap {
                    switch $0 {
                    case let .target(name: targetName, _):
                        return project.targets[targetName]?.productName
                    case let .project(target: targetName, path: projectPath, _):
                        return graph.projects[projectPath]?.targets[targetName]?.productName
                    default:
                        return nil
                    }
                }
                let implicitImports = targetImports.intersection(allTargetNames).subtracting(targetTuistDeclaredDependencies)
                if !implicitImports.isEmpty {
                    implicitTargetImports[target] = implicitImports
                }
            }
        }
        return implicitTargetImports
    }

    func imports(for target: XcodeGraph.Target) async throws -> Set<String> {
        var filesToScan = target.sources.map(\.path)
        if let headers = target.headers {
            filesToScan.append(contentsOf: headers.private)
            filesToScan.append(contentsOf: headers.public)
            filesToScan.append(contentsOf: headers.project)
        }
        var imports = Set(
            try await filesToScan.concurrentMap { file in
                try await self.matchPattern(at: file)
            }
            .flatMap { $0 }
        )
        imports.remove(target.productName)
        return imports
    }

    private func matchPattern(at path: AbsolutePath) async throws -> [String] {
        var language: ProgrammingLanguage
        switch path.extension {
        case "swift":
            language = .swift
        case "h", "m", "cpp", "mm":
            language = .objc
        default:
            return []
        }

        let sourceCode = try FileHandler.shared.readTextFile(path)
        return try importSourceCodeScanner.extractImports(
            from: sourceCode,
            language: language
        )
    }
}
