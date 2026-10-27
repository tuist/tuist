import XcodeProj

extension XCScheme {
    static func test(
        name: String = "DefaultScheme",
        lastUpgradeVersion: String = "1.3",
        version: String = "1.3",
        buildAction: BuildAction? = nil,
        testAction: TestAction? = nil,
        launchAction: LaunchAction? = nil,
        archiveAction: ArchiveAction? = nil,
        profileAction: ProfileAction? = nil,
        analyzeAction: AnalyzeAction? = nil,
        wasCreatedForAppExtension: Bool? = nil
    ) -> XCScheme {
        XCScheme(
            name: name,
            lastUpgradeVersion: lastUpgradeVersion,
            version: version,
            buildAction: buildAction,
            testAction: testAction,
            launchAction: launchAction,
            profileAction: profileAction,
            analyzeAction: analyzeAction,
            archiveAction: archiveAction,
            wasCreatedForAppExtension: wasCreatedForAppExtension
        )
    }
}
