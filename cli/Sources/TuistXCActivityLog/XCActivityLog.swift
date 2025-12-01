import Foundation

public struct XCActivityLog {
    public let version: Int8
    public let mainSection: XCActivityLogSection
    public let buildStep: XCActivityBuildStep
    public let category: XCActivityBuildCategory
    public let issues: [XCActivityIssue]
    public let files: [XCActivityBuildFile]
    public let targets: [XCActivityTarget]
    public let cacheableTasks: [CacheableTask]
    public let casOutputs: [CASOutput]
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
            targets: [XCActivityTarget] = [],
            cacheableTasks: [CacheableTask] = [],
            casOutputs: [CASOutput] = []
        ) -> XCActivityLog {
            XCActivityLog(
                version: version,
                mainSection: mainSection,
                buildStep: buildStep,
                category: category,
                issues: issues,
                files: files,
                targets: targets,
                cacheableTasks: cacheableTasks,
                casOutputs: casOutputs
            )
        }
    }
#endif
