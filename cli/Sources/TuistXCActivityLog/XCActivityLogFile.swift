import Foundation
import Path

public struct XCActivityLogFile: Equatable {
    public let path: AbsolutePath
    public let timeStoppedRecording: Date

    public init(
        path: AbsolutePath,
        timeStoppedRecording: Date
    ) {
        self.path = path
        self.timeStoppedRecording = timeStoppedRecording
    }
}

#if DEBUG
    extension XCActivityLogFile {
        public static func test(
            // swiftlint:disable:next force_try
            path: AbsolutePath = try! AbsolutePath(validating: "/udid.xcactivitylog"),
            timeStoppedRecording: Date = Date()
        ) -> XCActivityLogFile {
            XCActivityLogFile(
                path: path,
                timeStoppedRecording: timeStoppedRecording
            )
        }
    }
#endif
