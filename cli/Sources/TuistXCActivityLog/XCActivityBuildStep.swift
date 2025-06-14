import Foundation

public struct XCActivityBuildStep {
    public let errorCount: Int
}

#if DEBUG
    extension XCActivityBuildStep {
        public static func test(
            errorCount: Int = 0
        ) -> XCActivityBuildStep {
            XCActivityBuildStep(
                errorCount: errorCount
            )
        }
    }
#endif
