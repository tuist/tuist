import Foundation

public struct Dependencies: Equatable {
    public let carthageDependencies: [CarthageDependency]
    
    public init(
        carthageDependencies: [CarthageDependency]
    ) {
        self.carthageDependencies = carthageDependencies
    }
}
