import Foundation

public struct Dependencies: Equatable {
    public let carthage: CarthageDependencies?
    public let swiftPackageManager: SwiftPackageManagerDependencies?

    public init(
        carthage: CarthageDependencies?,
        swiftPackageManager: SwiftPackageManagerDependencies?
    ) {
        self.carthage = carthage
        self.swiftPackageManager = swiftPackageManager
    }
}
