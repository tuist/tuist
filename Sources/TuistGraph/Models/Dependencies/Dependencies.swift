import Foundation

public struct Dependencies: Equatable {
    public let swiftPackageManager: SwiftPackageManagerDependencies?
    public let platforms: Set<PackagePlatform>

    public init(
        swiftPackageManager: SwiftPackageManagerDependencies?,
        platforms: Set<PackagePlatform>
    ) {
        self.swiftPackageManager = swiftPackageManager
        self.platforms = platforms
    }
}
