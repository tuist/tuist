import Foundation

public struct Dependencies: Equatable {
    public let carthage: CarthageDependencies?
    public let swiftPackageManager: SwiftPackageManagerDependencies?
    public let platforms: Set<PackagePlatform>

    public init(
        carthage: CarthageDependencies?,
        swiftPackageManager: SwiftPackageManagerDependencies?,
        platforms: Set<PackagePlatform>
    ) {
        self.carthage = carthage
        self.swiftPackageManager = swiftPackageManager
        self.platforms = platforms
    }
}
