import Foundation

public struct XCActivityLog {
    public let version: Int8
    public let mainSection: XCActivityLogSection
    public let buildStep: XCActivityBuildStep
}

#if DEBUG
    extension XCActivityLog {
        public static func test(
            version: Int8 = 1,
            mainSection: XCActivityLogSection = .test(),
            buildStep: XCActivityBuildStep = .test()
        ) -> XCActivityLog {
            XCActivityLog(
                version: version,
                mainSection: mainSection,
                buildStep: buildStep
            )
        }
    }
#endif
