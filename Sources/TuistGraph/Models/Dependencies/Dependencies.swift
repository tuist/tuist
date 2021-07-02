import Foundation

public struct Dependencies: Equatable {
    public let carthage: CarthageDependencies?
    public let swiftPackageManager: SwiftPackageManagerDependencies?
    public let platforms: Set<Platform>

    public init(
        carthage: CarthageDependencies?,
        swiftPackageManager: SwiftPackageManagerDependencies?,
        platforms: Set<Platform>
    ) {
        self.carthage = carthage
        self.swiftPackageManager = swiftPackageManager
        self.platforms = platforms
    }
}
