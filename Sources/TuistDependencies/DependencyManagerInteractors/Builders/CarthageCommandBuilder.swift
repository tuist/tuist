import TSCBasic
import TuistSupport

// MARK: - Carthage Command Builder Error

enum CarthageCommandBuilderError: FatalError {
    case unrecognizedCommand
    
    /// Error type.
    var type: ErrorType {
        switch self {
        case .unrecognizedCommand:
            return .abort
        }
    }

    /// Description.
    var description: String {
        switch self {
        case .unrecognizedCommand:
            #warning("Provide description")
            return ""
        }
    }
}

// MARK: - Carthage Command Builder

#warning("Add unit test!")
final class CarthageCommandBuilder {
    
    // MARK: - Models
    
    enum Command: String {
        case update = "update"
        case fetch = "fetch"
    }
    
    enum Platform: String {
        case iOS = "iOS"
        case macOS = "macOS"
        case tvOS = "tvOS"
        case watchOS = "watchOS"
    }
    
    // MARK: - State
    
    private var command: Command?
    private var platforms: Set<Platform>?
    private var cacheBuilds: Bool = false
    private var newResolver: Bool = false
    
    // MARK: - Configurators
    
    @discardableResult
    func command(_ command: Command) -> Self {
        self.command = command
        return self
    }
    
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
    
    func build() throws -> String {
        var commandComponents: [String] = ["carthage"]
        
        // Command
        
        guard let command = command else {
            throw CarthageCommandBuilderError.unrecognizedCommand
        }
        commandComponents.append(command.rawValue)
        
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
        if newResolver { commandComponents.append("----new-resolver") }
        
        // Build
        
        return commandComponents.joined(separator: " ")
    }
}
