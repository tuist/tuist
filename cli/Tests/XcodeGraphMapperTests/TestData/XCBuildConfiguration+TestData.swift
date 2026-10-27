import XcodeProj

extension XCBuildConfiguration {
    static func testDebug(
        baseConfiguration: PBXFileReference? = nil,
        buildSettings: BuildSettings = MockDefaults.defaultDebugSettings
    ) -> XCBuildConfiguration {
        XCBuildConfiguration(
            name: "Debug",
            baseConfiguration: baseConfiguration,
            buildSettings: buildSettings
        )
    }

    static func testRelease(
        baseConfiguration: PBXFileReference? = nil,
        buildSettings: BuildSettings = MockDefaults.defaultReleaseSettings
    ) -> XCBuildConfiguration {
        XCBuildConfiguration(
            name: "Release",
            baseConfiguration: baseConfiguration,
            buildSettings: buildSettings
        )
    }
}
