import TSCBasic
import TuistCore
import TuistSupport

public class MockGeneratorModelLoader: GeneratorModelLoading {
    private var projects = [String: (AbsolutePath) throws -> Project]()
    private var workspaces = [String: (AbsolutePath) throws -> Workspace]()
    private var configs = [String: (AbsolutePath) throws -> Config]()
    private var plugins = [String: (AbsolutePath) throws -> Plugin]()

    private let basePath: AbsolutePath

    public init(basePath: AbsolutePath) {
        self.basePath = basePath
    }

    // MARK: - GeneratorModelLoading

    public func loadProject(at path: AbsolutePath) throws -> Project {
        try projects[path.pathString]!(path)
    }

    public func loadWorkspace(at path: AbsolutePath) throws -> Workspace {
        try workspaces[path.pathString]!(path)
    }

    public func loadConfig(at path: AbsolutePath) throws -> Config {
        try configs[path.pathString]!(path)
    }

    public func loadPlugin(at path: AbsolutePath) throws -> Plugin {
        try plugins[path.pathString]!(path)
    }

    // MARK: - Mock

    public func mockProject(_ path: String, loadClosure: @escaping (AbsolutePath) throws -> Project) {
        projects[basePath.appending(component: path).pathString] = loadClosure
    }

    public func mockWorkspace(_ path: String = "", loadClosure: @escaping (AbsolutePath) throws -> Workspace) {
        workspaces[basePath.appending(component: path).pathString] = loadClosure
    }

    public func mockConfig(_ path: String = "", loadClosure: @escaping (AbsolutePath) throws -> Config) {
        configs[basePath.appending(component: path).pathString] = loadClosure
    }

    public func mockPlugin(_ path: String = "", loadClosure: @escaping (AbsolutePath) throws -> Plugin) {
        plugins[path] = loadClosure
    }
}
