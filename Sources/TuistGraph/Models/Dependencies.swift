import Foundation

public struct Dependencies: Equatable {
    public let carthage: CarthageDependencies?

    public init(carthage: CarthageDependencies?) {
        self.carthage = carthage
    }
}
