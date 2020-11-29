import Foundation
import TSCBasic
import TuistCore
import TuistSupport

/// Saving frameworks installed using `carthage`.
public protocol CarthageFrameworksInteracting {
    /// Saves frameworks installed using `carthage`.
    /// - Parameters:
    ///   - carthageBuildDirectory: The path to the directory that contains the `Carthage/Build/` directory.
    ///   - dependenciesDirectory: The path to the directory that contains the `Tuist/Dependencies/` directory.
    func copyFrameworks(carthageBuildDirectory: AbsolutePath, dependenciesDirectory: AbsolutePath) throws
}

public final class CarthageFrameworksInteractor: CarthageFrameworksInteracting {
    private let fileHandler: FileHandling
 
    public init(fileHandler: FileHandling = FileHandler.shared) {
        self.fileHandler = fileHandler
    }

    public func copyFrameworks(carthageBuildDirectory: AbsolutePath, dependenciesDirectory: AbsolutePath) throws {
        let graphPath = dependenciesDirectory.appending(component: Constants.DependenciesDirectory.graphName)
        let graph = readGraph(graphPath: graphPath)
        
        var newGraph = Graph.empty
        
        try Platform.allCases.forEach { platform in
            let builtFrameworks: Set<String> = Set(try getBuiltFrameworks(carthageBuildDirectory: carthageBuildDirectory, platform: platform))
            
            try builtFrameworks.forEach {
                let carthageBuildFrameworkPath = buildCarthageBuildPath(frameworkName: $0, carthageBuildDirectory: carthageBuildDirectory, platform: platform)
                let destinationFramemorekPath = buildDestinationPath(frameworkName: $0, dependenciesDirectory: dependenciesDirectory, platform: platform)
                try copyDirectory(from: carthageBuildFrameworkPath, to: destinationFramemorekPath)
            }
            
            let existingFrameworks: Set<String> = Set(graph.dependencies(for: platform))
            let frameworksToDelete = existingFrameworks.subtracting(builtFrameworks)
            
            try frameworksToDelete.forEach {
                let destinationFrameworkPath = buildDestinationPath(frameworkName: $0, dependenciesDirectory: dependenciesDirectory, platform: platform)
                try deleteDirectory(at: destinationFrameworkPath)
            }
            
            newGraph = newGraph.updatingDependencies(Array(builtFrameworks), for: platform)
        }
        
        try saveGraph(graph: newGraph, graphPath: graphPath)
    }

    // MARK: - Helpers
    
    private func carthageBuildPathDirectory(carthageBuildDirectory: AbsolutePath, platform: Platform) -> AbsolutePath {
        switch platform {
        case .iOS, .watchOS, .tvOS:
            return carthageBuildDirectory.appending(component: platform.caseValue)
        case .macOS:
            return carthageBuildDirectory.appending(component: "Mac")
        }
    }
    
    private func buildCarthageBuildPath(frameworkName: String, carthageBuildDirectory: AbsolutePath, platform: Platform) -> AbsolutePath {
        carthageBuildPathDirectory(carthageBuildDirectory: carthageBuildDirectory, platform: platform).appending(component: "\(frameworkName).framework")
    }
    
    private func buildDestinationPath(frameworkName: String, dependenciesDirectory: AbsolutePath, platform: Platform) -> AbsolutePath {
        dependenciesDirectory.appending(components: frameworkName, platform.caseValue, "\(frameworkName).framework")
    }
    
    private func getBuiltFrameworks(carthageBuildDirectory: AbsolutePath, platform: Platform) throws -> [String] {
        let carthageBuildPath = carthageBuildPathDirectory(carthageBuildDirectory: carthageBuildDirectory, platform: platform)
        
        return try fileHandler
            .contentsOfDirectory(carthageBuildPath)
            .filter { $0.isFolder && $0.extension == "framework" }
            .compactMap { $0.components.last?.components(separatedBy: ".").first }
    }
    
    private func readGraph(graphPath: AbsolutePath) -> Graph {
        do {
            let decoder = JSONDecoder()
            let graphFileData = try fileHandler.readFile(graphPath)
            return try decoder.decode(Graph.self, from: graphFileData)
        } catch {
            return .empty
        }
    }
    
    private func saveGraph(graph: Graph, graphPath: AbsolutePath) throws {
        let encoder = JSONEncoder()
        let graphFileData = try encoder.encode(graph)
        try fileHandler.write(String(data: graphFileData, encoding: .utf8) ?? "", path: graphPath, atomically: true)
    }

    private func copyDirectory(from fromPath: AbsolutePath, to toPath: AbsolutePath) throws {
        try fileHandler.createFolder(toPath.removingLastComponent())

        if fileHandler.exists(toPath) {
            try fileHandler.delete(toPath)
        }

        try fileHandler.copy(from: fromPath, to: toPath)
    }
    
    private func deleteDirectory(at path: AbsolutePath) throws {
        if fileHandler.exists(path) {
            try fileHandler.delete(path)
        }
    }
}
