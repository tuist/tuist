import Foundation

public struct XCActivityLogSection {
    public let uniqueIdentifier: String
    public let timeStartedRecording: Double
    public var timeStoppedRecording: Double
}

#if DEBUG
    extension XCActivityLogSection {
        public static func test(
            uniqueIdentifier: String = "id",
            timeStartedRecording: Double = 10,
            timeStoppedRecording: Double = 20
        ) -> XCActivityLogSection {
            XCActivityLogSection(
                uniqueIdentifier: uniqueIdentifier,
                timeStartedRecording: timeStartedRecording,
                timeStoppedRecording: timeStoppedRecording
            )
        }
    }
#endif
