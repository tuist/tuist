import Foundation
import TSCBasic
import TuistSupport

public struct Project: Hashable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    // MARK: - Attributes

    /// Path to the folder that contains the project manifest.
    public var path: AbsolutePath

    /// Path to the root of the project sources.
    public var sourceRootPath: AbsolutePath

    /// Path to the Xcode project that will be generated.
    public var xcodeProjPath: AbsolutePath

    /// If any of the targets of the project has a dependency with CocoaPods,
    /// these paths points to the Xcode projects so that they get added to the generated workspace.
    public var podProjectPaths: Set<AbsolutePath>

    /// Project name.
    public var name: String

    /// Organization name.
    public var organizationName: String?

    /// Project targets.
    public var targets: [Target]

    /// Project swift packages.
    public var packages: [Package]

    /// Project schemes
    public var schemes: [Scheme]

    /// Project settings.
    public var settings: Settings

    /// The group to place project files within
    public var filesGroup: ProjectGroup

    /// Additional files to include in the project
    public var additionalFiles: [FileElement]

    // MARK: - Init

    /// Initializes the project with its attributes.
    ///
    /// - Parameters:
    ///   - path: Path to the folder that contains the project manifest.
    ///   - sourceRootPath: Path to the directory where the Xcode project will be generated.
    ///   - xcodeProjPath: Path to the Xcode project that will be generated.
    ///   - name: Project name.
    ///   - organizationName: Organization name.
    ///   - settings: The settings to apply at the project level
    ///   - filesGroup: The root group to place project files within
    ///   - targets: The project targets
    ///   - additionalFiles: The additional files to include in the project
    ///                      *(Those won't be included in any build phases)*
    ///   - podProjectPaths: If any of the targets of the project has a dependency with CocoaPods, these paths points to the Xcode projects so that they get added to the generated workspace.
    public init(path: AbsolutePath,
                sourceRootPath: AbsolutePath,
                xcodeProjPath: AbsolutePath,
                name: String,
                organizationName: String?,
                settings: Settings,
                filesGroup: ProjectGroup,
                targets: [Target],
                packages: [Package],
                schemes: [Scheme],
                additionalFiles: [FileElement],
                podProjectPaths: Set<AbsolutePath> = Set()) {
        self.path = path
        self.sourceRootPath = sourceRootPath
        self.xcodeProjPath = xcodeProjPath
        self.name = name
        self.organizationName = organizationName
        self.targets = targets
        self.packages = packages
        self.schemes = schemes
        self.settings = settings
        self.filesGroup = filesGroup
        self.additionalFiles = additionalFiles
        self.podProjectPaths = podProjectPaths
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

    // MARK: - CustomDebugStringConvertible

    public var debugDescription: String {
        name
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }

    // MARK: - Public

    /// Returns a copy of the project with the given targets set.
    /// - Parameter targets: Targets to be set to the copy.
    public func with(targets: [Target]) -> Project {
        Project(path: path,
                sourceRootPath: sourceRootPath,
                xcodeProjPath: xcodeProjPath,
                name: name,
                organizationName: organizationName,
                settings: settings,
                filesGroup: filesGroup,
                targets: targets,
                packages: packages,
                schemes: schemes,
                additionalFiles: additionalFiles,
                podProjectPaths: podProjectPaths)
    }

    /// Returns a copy of the project with the given schemes set.
    /// - Parameter schemes: Schemes to be set to the copy.
    public func with(schemes: [Scheme]) -> Project {
        Project(path: path,
                sourceRootPath: sourceRootPath,
                xcodeProjPath: xcodeProjPath,
                name: name,
                organizationName: organizationName,
                settings: settings,
                filesGroup: filesGroup,
                targets: targets,
                packages: packages,
                schemes: schemes,
                additionalFiles: additionalFiles,
                podProjectPaths: podProjectPaths)
    }

    /// Returns the name of the default configuration.
    public var defaultDebugBuildConfigurationName: String {
        let debugConfiguration = settings.defaultDebugBuildConfiguration()
        let buildConfiguration = debugConfiguration ?? settings.configurations.keys.first
        return buildConfiguration?.name ?? BuildConfiguration.debug.name
    }
}
