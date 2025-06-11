import Foundation

public struct XCActivityLog {
    public let version: Int8
    public let mainSection: XCActivityLogSection
    public let buildStep: XCActivityBuildStep
    public let category: XCActivityBuildCategory
    public let issues: [XCActivityIssue]
    public let files: [XCActivityBuildFile]
    public let targets: [XCActivityTarget]
}

#if DEBUG
    extension XCActivityLog {
        public static func test(
            version: Int8 = 1,
            mainSection: XCActivityLogSection = .test(),
            buildStep: XCActivityBuildStep = .test(),
            category: XCActivityBuildCategory = .clean,
            issues: [XCActivityIssue] = [],
            files: [XCActivityBuildFile] = [],
            targets: [XCActivityTarget] = []
        ) -> XCActivityLog {
            XCActivityLog(
                version: version,
                mainSection: mainSection,
                buildStep: buildStep,
                category: category,
                issues: issues,
                files: files,
                targets: targets
            )
        }
    }
#endif
