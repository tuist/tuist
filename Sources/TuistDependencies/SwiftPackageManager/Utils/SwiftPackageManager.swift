import TSCBasic
import TuistGraph
import TuistSupport

/// Protocol that defines an interface to interact with the Swift Package Manager.
public protocol SwiftPackageManaging {
    /// Resolve package dependencies.
    /// - Parameter path: Directory where the `Package.swift` is defined.
    func resolve(at path: AbsolutePath) throws
}

public final class SwiftPackageManager: SwiftPackageManaging {
    public init() { }
    
    public func resolve(at path: AbsolutePath) throws {
        let command = [
            "swift",
            "package",
            "--package-path",
            path.pathString,
            "resolve"
        ]
        
        try System.shared.run(command)
    }
}
