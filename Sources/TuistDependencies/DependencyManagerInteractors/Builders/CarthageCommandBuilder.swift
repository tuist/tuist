import TSCBasic
import TuistSupport

// MARK: - Carthage Command Builder

#warning("Add unit test!")
final class CarthageCommandBuilder {
    
    // MARK: - Models

    enum Platform: String {
        case iOS = "iOS"
        case macOS = "macOS"
        case tvOS = "tvOS"
        case watchOS = "watchOS"
    }
    
    // MARK: - State
    
    private let method: InstallDependenciesMethod
    private let path: AbsolutePath
    private var platforms: Set<Platform>?
    private var cacheBuilds: Bool = false
    private var newResolver: Bool = false
    
    // MARK: - Init
    
    init(method: InstallDependenciesMethod, path: AbsolutePath) {
        self.method = method
        self.path = path
    }
    
    // MARK: - Configurators
    
    @discardableResult
    func platforms(_ platforms: Set<Platform>) -> Self {
        self.platforms = platforms
        return self
    }
    
    @discardableResult
    func cacheBuilds(_ cacheBuilds: Bool) -> Self {
        self.cacheBuilds = cacheBuilds
        return self
    }
    
    @discardableResult
    func newResolver(_ newResolver: Bool) -> Self {
        self.newResolver = newResolver
        return self
    }
    
    // MARK: - Build
    
    func build() -> [String] {
        var commandComponents: [String] = ["carthage"]
        
        // Command
        
        switch method {
        case .fetch: commandComponents.append("bootstrap")
        case .update: commandComponents.append("update")
        }
        
        // Project Directory
        
        commandComponents.append("--project-directory")
        commandComponents.append(path.pathString)
        
        // Platforms

        if let platforms = platforms, !platforms.isEmpty {
            commandComponents.append("--platform")
            commandComponents.append(
                platforms
                    .map { $0.rawValue }
                    .joined(separator: ",")
            )
        }

        // Flags

        if cacheBuilds { commandComponents.append("--cache-builds") }
        if newResolver { commandComponents.append("--new-resolver") }
        
        // Build
        
        return commandComponents
    }
}
