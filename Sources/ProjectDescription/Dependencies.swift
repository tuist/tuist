import Foundation

public struct Dependencies: Codable, Equatable {
    public let carthage: [CarthageDependency]

    public init(carthage: [CarthageDependency] = []) {
        self.carthage = carthage
        dumpIfNeeded(self)
    }
}
