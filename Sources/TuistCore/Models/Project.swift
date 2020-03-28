import Basic
import Foundation
import TuistSupport

public class Project: Equatable, CustomStringConvertible {
    public static func == (lhs: Project, rhs: Project) -> Bool {
        lhs.path == rhs.path &&
            lhs.name == rhs.name &&
            lhs.organizationName == rhs.organizationName &&
            lhs.fileName == rhs.fileName &&
            lhs.targets == rhs.targets &&
            lhs.packages == rhs.packages &&
            lhs.schemes == rhs.schemes &&
            lhs.autogenerateSchemes == rhs.autogenerateSchemes &&
            lhs.settings == rhs.settings &&
            lhs.filesGroup == rhs.filesGroup &&
            lhs.additionalFiles == rhs.additionalFiles
    }

    // MARK: - Attributes

    /// Path to the folder that contains the project manifest.
    public let path: AbsolutePath

    /// Project name.
    public let name: String

    /// Organization name.
    public let organizationName: String?

    /// Project file name.
    public let fileName: String

    /// Project targets.
    public private(set) var targets: [Target]

    /// Project swift packages.
    public let packages: [Package]

    /// Project schemes
    public let schemes: [Scheme]

    /// Auto generate default schemes
    public let autogenerateSchemes: Bool

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
    ///   - organizationName: Organization name.
    ///   - settings: The settings to apply at the project level
    ///   - filesGroup: The root group to place project files within
    ///   - targets: The project targets
    ///   - additionalFiles: The additional files to include in the project
    ///                      *(Those won't be included in any build phases)*
    public init(path: AbsolutePath,
                name: String,
                organizationName: String? = nil,
                fileName: String? = nil,
                settings: Settings,
                filesGroup: ProjectGroup,
                targets: [Target] = [],
                packages: [Package] = [],
                schemes: [Scheme] = [],
                autogenerateSchemes: Bool = true,
                additionalFiles: [FileElement] = []) {
        self.path = path
        self.name = name
        self.organizationName = organizationName
        self.fileName = fileName ?? name
        self.targets = targets
        self.packages = packages
        self.schemes = schemes
        self.autogenerateSchemes = autogenerateSchemes
        self.settings = settings
        self.filesGroup = filesGroup
        self.additionalFiles = additionalFiles
    }

    /// It returns the project targets sorted based on the target type and the dependencies between them.
    /// The most dependent and non-tests targets are sorted first in the list.
    ///
    /// - Parameter graph: Dependencies graph.
    /// - Returns: Sorted targets.
    public func sortedTargetsForProjectScheme(graph: Graph) -> [Target] {
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

    // MARK: - Public

    /// Returns a copy of the project with the given targets set.
    /// - Parameter targets: Targets to be set to the copy.
    public func with(targets: [Target]) -> Project {
        Project(path: path,
                name: name,
                organizationName: organizationName,
                fileName: fileName,
                settings: settings,
                filesGroup: filesGroup,
                targets: targets,
                packages: packages,
                schemes: schemes,
                autogenerateSchemes: autogenerateSchemes,
                additionalFiles: additionalFiles)
    }
}
