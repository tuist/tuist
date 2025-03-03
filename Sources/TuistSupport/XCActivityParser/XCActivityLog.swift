import Foundation

public struct XCActivityLog {
    public let version: Int8
    public let mainSection: XCActivityLogSection
}

#if DEBUG
    extension XCActivityLog {
        public static func test(
            version: Int8 = 1,
            mainSection: XCActivityLogSection = .test()
        ) -> XCActivityLog {
            XCActivityLog(
                version: version,
                mainSection: mainSection
            )
        }
    }
#endif
