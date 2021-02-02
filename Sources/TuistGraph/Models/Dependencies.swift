import Foundation

public struct Dependencies: Equatable {
    public let carthageDependencies: [CarthageDependency]
    public let swiftPackageManagerDependencies: [SwiftPackageManagerDependency]

    public init(
        carthageDependencies: [CarthageDependency],
        swiftPackageManagerDependencies: [SwiftPackageManagerDependency]
    ) {
        self.carthageDependencies = carthageDependencies
        self.swiftPackageManagerDependencies = swiftPackageManagerDependencies
    }
}
