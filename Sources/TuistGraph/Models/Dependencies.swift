import Foundation

public struct Dependencies: Equatable {
    public let carthageDependencies: CarthageDependencies?

    public init(
        carthageDependencies: CarthageDependencies?
    ) {
        self.carthageDependencies = carthageDependencies
    }
}
