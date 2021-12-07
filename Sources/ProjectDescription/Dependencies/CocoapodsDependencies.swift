import Foundation

/// Contains the description of dependencies that can be installed using CocoaPods.
public struct CocoaPodsDependencies: Codable, Equatable {
    /// List of pods that will be installed using CocoaPods
    public let pods: [Pod]

    init(pods: [Pod]) {
        self.pods = pods
    }
    
    /// Returns a group of CocoaPods' dependencies
    /// - Parameter pods: Pods' definitions.
    /// - Returns: An instance of CocoaPodsDependencies.
    public static func pods(_ pods: [Pod]) -> CocoaPodsDependencies {
        return CocoaPodsDependencies(pods: pods)
    }
}

// MARK: - ExpressibleByArrayLiteral

extension CocoaPodsDependencies: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Pod...) {
        self.init(pods: elements)
    }
}
