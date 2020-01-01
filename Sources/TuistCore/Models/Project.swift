import Basic
import Foundation
import TuistSupport

public struct Project: Equatable, CustomStringConvertible {
    // MARK: - Attributes

    /// Path to the folder that contains the project manifest.
    public let path: AbsolutePath

    /// Project name.
    public let name: String

    /// Project file name.
    public private(set) var fileName: String

    /// Project targets.
    public private(set) var targets: [Target]

    /// Project swift packages.
    public let packages: [Package]

    /// Project schemes
    public let schemes: [Scheme]

    /// Project settings.
    public let settings: Settings

    /// The group to place project files within
    public let filesGroup: ProjectGroup

    /// Additional files to include in the project
    public let additionalFiles: [FileElement]

    // MARK: - Init

    /// Initializes the project with its attributes.
    ///
    /// - Parameters:
    ///   - path: Path to the folder that contains the project manifest.
    ///   - name: Project name.
    ///   - settings: The settings to apply at the project level
    ///   - filesGroup: The root group to place project files within
    ///   - targets: The project targets
    ///   - additionalFiles: The additional files to include in the project
    ///                      *(Those won't be included in any build phases)*
    public init(path: AbsolutePath,
                name: String,
                fileName: String? = nil,
                settings: Settings,
                filesGroup: ProjectGroup,
                targets: [Target] = [],
                packages: [Package] = [],
                schemes: [Scheme] = [],
                additionalFiles: [FileElement] = []) {
        self.path = path
        self.name = name
        self.fileName = fileName ?? name
        self.targets = targets
        self.packages = packages
        self.schemes = schemes
        self.settings = settings
        self.filesGroup = filesGroup
        self.additionalFiles = additionalFiles
    }

    /// It returns the project targets sorted based on the target type and the dependencies between them.
    /// The most dependent and non-tests targets are sorted first in the list.
    ///
    /// - Parameter graph: Dependencies graph.
    /// - Returns: Sorted targets.
    public func sortedTargetsForProjectScheme(graph: Graphing) -> [Target] {
        targets.sorted { (first, second) -> Bool in
            // First criteria: Test bundles at the end
            if first.product.testsBundle, !second.product.testsBundle {
                return false
            }
            if !first.product.testsBundle, second.product.testsBundle {
                return true
            }

            // Second criteria: Most dependent targets first.
            let secondDependencies = graph.targetDependencies(path: self.path, name: second.name)
                .filter { $0.path == self.path }
                .map { $0.target.name }
            let firstDependencies = graph.targetDependencies(path: self.path, name: first.name)
                .filter { $0.path == self.path }
                .map { $0.target.name }

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

    public var description: String {
        name
    }

    // MARK: - Equatable

    public static func == (lhs: Project, rhs: Project) -> Bool {
        lhs.path == rhs.path &&
            lhs.name == rhs.name &&
            lhs.targets == rhs.targets &&
            lhs.schemes == rhs.schemes &&
            lhs.settings == rhs.settings
    }

    /// Creates a copy of the project and sets the given list of targets.
    /// - Parameter targets: List of targets to be set to the copy.
    public func with(targets: [Target]) -> Project {
        var project = self
        project.targets = targets
        return project
    }

    /// Returns a copy of the project with the given target added.
    /// - Parameter target: Target to be added.
    public func adding(target: Target) -> Project {
        var project = self
        var targets = project.targets
        targets.append(target)
        project.targets = targets

        return project
    }

    /// Returns a copy of the project with the given file name.
    /// - Parameter fileName: Project file name.
    public func with(fileName: String) -> Project {
        var project = self
        project.fileName = fileName
        return project
    }
}
