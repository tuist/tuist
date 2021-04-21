import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

// MARK: - Carthage Command Generating

/// Protocol that defines an interface to interact with the Carthage.
public protocol Carthaging {
    /// Checkouts and builds the project's dependencies
    /// - Parameters:
    ///   - path: Directory whose project's dependencies will be installed.
    ///   - platforms: The platforms to build for.
    ///   - options: The options for Carthage installation.
    func bootstrap(at path: AbsolutePath, platforms: Set<Platform>?, options: Set<CarthageDependencies.Options>?) throws
    
    /// Updates and rebuilds the project's dependencies
    /// - Parameters:
    ///   - path: Directory whose project's dependencies will be installed.
    ///   - platforms: The platforms to build for.
    ///   - options: The options for Carthage installation.
    func update(at path: AbsolutePath, platforms: Set<Platform>?, options: Set<CarthageDependencies.Options>?) throws
}

// MARK: - Carthage Command Generator

public final class Carthage: Carthaging {
    public init() {}
    
    public func bootstrap(at path: AbsolutePath, platforms: Set<Platform>?, options: Set<CarthageDependencies.Options>?) throws {
        var commandComponents: [String] = []
        commandComponents.append("carthage")
        commandComponents.append("bootstrap")

        commandComponents += projectDirecotryFlag(for: path)
        commandComponents += plarformFlag(for: platforms)
        commandComponents += additionalFlags(with: options)
        
        try System.shared.run(commandComponents)
    }
    
    public func update(at path: AbsolutePath, platforms: Set<Platform>?, options: Set<CarthageDependencies.Options>?) throws {
        var commandComponents: [String] = []
        commandComponents.append("carthage")
        commandComponents.append("update")

        commandComponents += projectDirecotryFlag(for: path)
        commandComponents += plarformFlag(for: platforms)
        commandComponents += additionalFlags(with: options)
        
        try System.shared.run(commandComponents)
    }
    
    // MARK: - Helpers
    
    private func projectDirecotryFlag(for path: AbsolutePath) -> [String] {
        [
            "--project-directory",
            path.pathString,
        ]
    }
    
    private func plarformFlag(for platforms: Set<Platform>?) -> [String] {
        guard let platforms = platforms, !platforms.isEmpty  else { return [] }
        
        return [
            "--platform",
            platforms
                .map(\.caseValue)
                .sorted()
                .joined(separator: ","),
        ]
    }
    
    private func additionalFlags(with options: Set<CarthageDependencies.Options>?) -> [String] {
        var flags = [
            "--use-netrc",
            "--cache-builds",
            "--new-resolver",
        ]
        
        if let options = options {
            if options.contains(.useXCFrameworks) {
                flags.append("--use-xcframeworks")
            }

            if options.contains(.noUseBinaries) {
                flags.append("--no-use-binaries")
            }
        }
        
        return flags
    }
}

