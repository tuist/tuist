import TSCBasic
import TuistSupport

// MARK: - Carthage Interacting

public protocol CarthageInteracting: DependencyManagerInteracting {
}

// MARK: - Carthage Interactor

public final class CarthageInteractor: CarthageInteracting {
    public var isAvailable: Bool { canUseCarthageThroughBundler() || canUseSystemCarthage() }
    
    public init() { }
    
    public func install(method: InstallDependenciesMethod) throws {
        let carthageCommand: CarthageCommandBuilder.Command = {
            switch method {
            case .fetch: return .fetch
            case .update: return .update
            }
        }()
        
        #warning("TODO: how to determine platforms?")
        let command = try CarthageCommandBuilder()
            .command(carthageCommand)
            .platforms([.iOS, .macOS])
            .cacheBuilds(true)
            .newResolver(true)
            .build()
    }
    
    // MARK: - Helpers
    
    /// Returns true if CocoaPods is accessible through Bundler,
    /// and shoudl be used instead of the global CocoaPods.
    /// - Returns: True if Bundler can execute CocoaPods.
    private func canUseCarthageThroughBundler() -> Bool {
        do {
            try System.shared.run(["bundle", "info", "carthage"])
            return true
        } catch {
            return false
        }
    }

    /// Returns true if Carthage is avaiable in the environment.
    /// - Returns: True if Carthege is available globally in the system.
    private func canUseSystemCarthage() -> Bool {
        do {
            _ = try System.shared.which("carthage")
            return true
        } catch {
            return false
        }
    }
}
