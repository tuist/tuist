import Foundation

@testable import TuistDependencies

public extension PackageInfo {
    static func test(
        name: String = "Package",
        platforms: [PlatformInfo] = [],
        toolsVersion: ToolsVersion = .test()
    ) -> Self {
        .init(
            name: name,
            platforms: platforms,
            toolsVersion: toolsVersion
        )
    }
}

public extension PackageInfo.ToolsVersion {
    static func test(
        varsion: String = "1.0.0"
    ) -> Self {
        .init(
            version: varsion
        )
    }
}
