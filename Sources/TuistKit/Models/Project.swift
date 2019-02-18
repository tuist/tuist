import Basic
import Foundation
import TuistCore

class Project: Equatable, CustomStringConvertible {
    // MARK: - Attributes

    /// Path to the folder that contains the project manifest.
    let path: AbsolutePath

    /// Project name.
    let name: String

    /// Project targets.
    let targets: [Target]

    /// Project settings.
    let settings: Settings?

    // MARK: - Init

    /// Initializes the project with its attributes.
    ///
    /// - Parameters:
    ///   - path: Path to the folder that contains the project manifest.
    ///   - name: Project name.
    ///   - targets: Project settings.
    init(path: AbsolutePath,
         name: String,
         settings: Settings? = nil,
         targets: [Target]) {
        self.path = path
        self.name = name
        self.targets = targets
        self.settings = settings
    }

    // MARK: - Init

    /// Parses the project manifest at the given path and returns a Project instance with the representation.
    ///
    /// - Parameters:
    ///   - path: Path to the folder that contains the project manifest.
    ///   - cache: Cache instance to cache projects and dependencies.
    ///   - circularDetector: Utility to find circular dependencies between targets.
    /// - Returns: Initialized project.
    /// - Throws: An error if the project has an invalid format.
    static func at(_ path: AbsolutePath, cache: GraphLoaderCaching, circularDetector: GraphCircularDetecting) throws -> Project {
        if let project = cache.project(path) {
            return project
        } else {
            let project = try Project(path: path, cache: cache)
            cache.add(project: project)

            for target in project.targets {
                if cache.targetNode(path, name: target.name) != nil { continue }
                _ = try TargetNode.read(name: target.name, path: path, cache: cache, circularDetector: circularDetector)
            }

            return project
        }
    }

    init(path: AbsolutePath,
         cache _: GraphLoaderCaching,
         fileHandler: FileHandling = FileHandler(),
         manifestLoader: GraphManifestLoading = GraphManifestLoader()) throws {
        let json = try manifestLoader.load(.project, path: path)
        self.path = path
        name = try json.get("name")
        let targetsJSONs: [JSON] = try json.get("targets")
        targets = try targetsJSONs.map({ try Target(dictionary: $0, projectPath: path, fileHandler: fileHandler) })
        let settingsJSON: JSON? = try? json.get("settings")
        settings = try settingsJSON.map({ try Settings(dictionary: $0, projectPath: path, fileHandler: fileHandler) })
    }
    
    /// It returns the project targets sorted based on the target type and the dependencies between them.
    /// The most dependent and non-tests targets are sorted first in the list.
    ///
    /// - Parameter graph: Dependencies graph.
    /// - Returns: Sorted targets.
    func sortedTargetsForProjectScheme(graph: Graphing) -> [Target] {
        return targets.sorted { (first, second) -> Bool in
            // First criteria: Test bundles at the end
            if first.product.testsBundle && !second.product.testsBundle {
                return false
            }
            if !first.product.testsBundle && second.product.testsBundle {
                return true
            }
            
            // Second criteria: Most dependent targets first.
            let secondDependencies = graph.targetDependencies(path: self.path, name: second.name)
                .filter({ $0.path == self.path })
                .map({ $0.target.name })
            let firstDependencies = graph.targetDependencies(path: self.path, name: first.name)
                .filter({ $0.path == self.path })
                .map({ $0.target.name })
            
            if secondDependencies.contains(first.name) {
                return true
            } else if firstDependencies.contains(second.name) {
                return false
                
                // Third criteria: Name
            } else {
                return first.name < second.name
            }
        }
    }
    
    // MARK: - CustomStringConvertible
    
    var description: String {
        return self.name
    }

    // MARK: - Equatable

    static func == (lhs: Project, rhs: Project) -> Bool {
        return lhs.path == rhs.path &&
            lhs.name == rhs.name &&
            lhs.targets == rhs.targets &&
            lhs.settings == rhs.settings
    }
}
