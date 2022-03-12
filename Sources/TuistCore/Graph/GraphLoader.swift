import Foundation
import TSCBasic
import TuistGraph

// MARK: - GraphLoading

public protocol GraphLoading {
    func loadWorkspace(workspace: Workspace, projects: [Project]) throws -> Graph
}

// MARK: - GraphLoader

// swiftlint:disable:next type_body_length
public final class GraphLoader: GraphLoading {
    private let frameworkMetadataProvider: FrameworkMetadataProviding
    private let libraryMetadataProvider: LibraryMetadataProviding
    private let xcframeworkMetadataProvider: XCFrameworkMetadataProviding
    private let systemFrameworkMetadataProvider: SystemFrameworkMetadataProviding

    public convenience init() {
        self.init(
            frameworkMetadataProvider: FrameworkMetadataProvider(),
            libraryMetadataProvider: LibraryMetadataProvider(),
            xcframeworkMetadataProvider: XCFrameworkMetadataProvider(),
            systemFrameworkMetadataProvider: SystemFrameworkMetadataProvider()
        )
    }

    public init(
        frameworkMetadataProvider: FrameworkMetadataProviding,
        libraryMetadataProvider: LibraryMetadataProviding,
        xcframeworkMetadataProvider: XCFrameworkMetadataProviding,
        systemFrameworkMetadataProvider: SystemFrameworkMetadataProviding
    ) {
        self.frameworkMetadataProvider = frameworkMetadataProvider
        self.libraryMetadataProvider = libraryMetadataProvider
        self.xcframeworkMetadataProvider = xcframeworkMetadataProvider
        self.systemFrameworkMetadataProvider = systemFrameworkMetadataProvider
    }

    // MARK: - GraphLoading

    public func loadWorkspace(workspace: Workspace, projects: [Project]) throws -> Graph {
        let cache = Cache(projects: projects)

        try workspace.projects.forEach {
            try loadProject(
                path: $0,
                cache: cache
            )
        }

        let updatedWorkspace = workspace.replacing(projects: cache.loadedProjects.keys.sorted())
        let graph = Graph(
            name: updatedWorkspace.name,
            path: updatedWorkspace.path,
            workspace: updatedWorkspace,
            projects: cache.loadedProjects,
            packages: cache.packages,
            targets: cache.loadedTargets,
            dependencies: cache.dependencies
        )
        return graph
    }

    // MARK: - Private

    private func loadProject(
        path: AbsolutePath,
        cache: Cache
    ) throws {
        guard !cache.projectLoaded(path: path) else {
            return
        }
        guard let project = cache.allProjects[path] else {
            throw GraphLoadingError.missingProject(path)
        }
        cache.add(project: project)

        try project.targets.forEach {
            try loadTarget(
                path: path,
                name: $0.name,
                cache: cache
            )
        }
    }

    private func loadTarget(
        path: AbsolutePath,
        name: String,
        cache: Cache
    ) throws {
        guard !cache.targetLoaded(path: path, name: name) else {
            return
        }
        guard cache.allProjects[path] != nil else {
            throw GraphLoadingError.missingProject(path)
        }
        guard let referencedTargetProject = cache.allTargets[path],
              let target = referencedTargetProject[name]
        else {
            throw GraphLoadingError.targetNotFound(name, path)
        }

        cache.add(target: target, path: path)
        let dependencies = try target.dependencies.map {
            try loadDependency(
                path: path,
                fromPlatform: target.platform,
                dependency: $0,
                cache: cache
            )
        }

        if !dependencies.isEmpty {
            cache.dependencies[.target(name: name, path: path)] = Set(dependencies)
        }
    }

    private func loadDependency(
        path: AbsolutePath,
        fromPlatform: Platform,
        dependency: TargetDependency,
        cache: Cache
    ) throws -> GraphDependency {
        switch dependency {
        case let .target(toTarget):
            // A target within the same project.
            try loadTarget(
                path: path,
                name: toTarget,
                cache: cache
            )
            return .target(name: toTarget, path: path)

        case let .project(toTarget, projectPath):
            // A target from another project
            try loadProject(path: projectPath, cache: cache)
            try loadTarget(
                path: projectPath,
                name: toTarget,
                cache: cache
            )
            return .target(name: toTarget, path: projectPath)

        case let .framework(frameworkPath):
            return try loadFramework(path: frameworkPath, cache: cache)

        case let .library(libraryPath, publicHeaders, swiftModuleMap):
            return try loadLibrary(
                path: libraryPath,
                publicHeaders: publicHeaders,
                swiftModuleMap: swiftModuleMap,
                cache: cache
            )

        case let .xcframework(frameworkPath):
            return try loadXCFramework(path: frameworkPath, cache: cache)

        case let .sdk(name, status):
            return try loadSDK(name: name, platform: fromPlatform, status: status, source: .system)

        case let .package(product):
            return try loadPackage(fromPath: path, productName: product)

        case .xctest:
            return try loadXCTestSDK(platform: fromPlatform)
        }
    }

    private func loadFramework(path: AbsolutePath, cache: Cache) throws -> GraphDependency {
        if let loaded = cache.frameworks[path] {
            return loaded
        }

        let metadata = try frameworkMetadataProvider.loadMetadata(at: path)
        let framework: GraphDependency = .framework(
            path: metadata.path,
            binaryPath: metadata.binaryPath,
            dsymPath: metadata.dsymPath,
            bcsymbolmapPaths: metadata.bcsymbolmapPaths,
            linking: metadata.linking,
            architectures: metadata.architectures,
            isCarthage: metadata.isCarthage
        )
        cache.add(framework: framework, at: path)
        return framework
    }

    private func loadLibrary(
        path: AbsolutePath,
        publicHeaders: AbsolutePath,
        swiftModuleMap: AbsolutePath?,
        cache: Cache
    ) throws -> GraphDependency {
        if let loaded = cache.libraries[path] {
            return loaded
        }

        let metadata = try libraryMetadataProvider.loadMetadata(
            at: path,
            publicHeaders: publicHeaders,
            swiftModuleMap: swiftModuleMap
        )
        let library: GraphDependency = .library(
            path: metadata.path,
            publicHeaders: metadata.publicHeaders,
            linking: metadata.linking,
            architectures: metadata.architectures,
            swiftModuleMap: metadata.swiftModuleMap
        )
        cache.add(library: library, at: path)
        return library
    }

    private func loadXCFramework(path: AbsolutePath, cache: Cache) throws -> GraphDependency {
        if let loaded = cache.xcframeworks[path] {
            return loaded
        }

        let metadata = try xcframeworkMetadataProvider.loadMetadata(at: path)
        let xcframework: GraphDependency = .xcframework(
            path: metadata.path,
            infoPlist: metadata.infoPlist,
            primaryBinaryPath: metadata.primaryBinaryPath,
            linking: metadata.linking
        )
        cache.add(xcframework: xcframework, at: path)
        return xcframework
    }

    private func loadSDK(
        name: String,
        platform: Platform,
        status: SDKStatus,
        source: SDKSource
    ) throws -> GraphDependency {
        let metadata = try systemFrameworkMetadataProvider.loadMetadata(
            sdkName: name,
            status: status,
            platform: platform,
            source: source
        )
        return .sdk(name: metadata.name, path: metadata.path, status: metadata.status, source: metadata.source)
    }

    private func loadXCTestSDK(platform: Platform) throws -> GraphDependency {
        let metadata = try systemFrameworkMetadataProvider.loadXCTestMetadata(platform: platform)
        return .sdk(name: metadata.name, path: metadata.path, status: metadata.status, source: metadata.source)
    }

    private func loadPackage(fromPath: AbsolutePath, productName: String) throws -> GraphDependency {
        // TODO: `fromPath` isn't quite correct as it reflects the path where the dependency was declared
        // and doesn't uniquely identify it. It's been copied from the previous implementation to maintain
        // existing behaviour and should be fixed separately
        .packageProduct(
            path: fromPath,
            product: productName
        )
    }

    final class Cache {
        let allProjects: [AbsolutePath: Project]
        let allTargets: [AbsolutePath: [String: Target]]

        var loadedProjects: [AbsolutePath: Project] = [:]
        var loadedTargets: [AbsolutePath: [String: Target]] = [:]
        var dependencies: [GraphDependency: Set<GraphDependency>] = [:]
        var frameworks: [AbsolutePath: GraphDependency] = [:]
        var libraries: [AbsolutePath: GraphDependency] = [:]
        var xcframeworks: [AbsolutePath: GraphDependency] = [:]
        var packages: [AbsolutePath: [String: Package]] = [:]

        init(projects: [Project]) {
            let allProjects = Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })
            let allTargets = allProjects.mapValues {
                Dictionary(uniqueKeysWithValues: $0.targets.map { ($0.name, $0) })
            }
            self.allProjects = allProjects
            self.allTargets = allTargets
        }

        func add(project: Project) {
            loadedProjects[project.path] = project
            project.packages.forEach {
                packages[project.path, default: [:]][$0.name] = $0
            }
        }

        func add(target: Target, path: AbsolutePath) {
            loadedTargets[path, default: [:]][target.name] = target
        }

        func add(framework: GraphDependency, at path: AbsolutePath) {
            frameworks[path] = framework
        }

        func add(xcframework: GraphDependency, at path: AbsolutePath) {
            xcframeworks[path] = xcframework
        }

        func add(library: GraphDependency, at path: AbsolutePath) {
            libraries[path] = library
        }

        func targetLoaded(path: AbsolutePath, name: String) -> Bool {
            loadedTargets[path]?[name] != nil
        }

        func projectLoaded(path: AbsolutePath) -> Bool {
            loadedProjects[path] != nil
        }
    }
}

extension Package {
    fileprivate var name: String {
        switch self {
        case let .local(path: path):
            return path.pathString
        case let .remote(url: url, requirement: _):
            return url
        }
    }
}
