import Foundation

@testable import TuistDependencies

public extension PackageInfo {
    static func test(
        name: String = "Package",
        platforms: [Platform] = [],
        toolsVersion: ToolsVersion = .test(),
        cLanguageStandard: String? = nil,
        cxxLanguageStandard: String? = nil
    ) -> Self {
        .init(
            name: name,
            platforms: platforms,
            toolsVersion: toolsVersion,
            cLanguageStandard: cLanguageStandard,
            cxxLanguageStandard: cxxLanguageStandard
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
