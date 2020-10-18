import TSCBasic
import TuistSupport

public protocol CarthageManaging: DependencyManaging {
}

public final class CarthageManager: CarthageManaging {
    public var isAvailable: Bool { canUseCarthageThroughBundler() || canUseSystemCarthage() }
    
    public init() { }
    
    public func install(method: InstallDependenciesMethod) throws {
        
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
