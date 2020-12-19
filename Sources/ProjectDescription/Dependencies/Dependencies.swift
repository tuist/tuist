import Foundation

public struct Dependencies: Codable, Equatable {
    public let dependencies: [Dependency]

    public init(_ dependencies: [Dependency] = []) {
        self.dependencies = dependencies
        dumpIfNeeded(self)
    }
}
