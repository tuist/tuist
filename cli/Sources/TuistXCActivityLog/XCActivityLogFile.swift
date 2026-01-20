import Foundation
import Path

public struct XCActivityLogFile: Equatable {
    public let path: AbsolutePath
    public let timeStoppedRecording: Date
    public let signature: String

    public init(
        path: AbsolutePath,
        timeStoppedRecording: Date,
        signature: String
    ) {
        self.path = path
        self.timeStoppedRecording = timeStoppedRecording
        self.signature = signature
    }
}

#if DEBUG
    extension XCActivityLogFile {
        public static func test(
            // swiftlint:disable:next force_try
            path: AbsolutePath = try! AbsolutePath(validating: "/udid.xcactivitylog"),
            timeStoppedRecording: Date = Date(),
            signature: String = "Build Tuist"
        ) -> XCActivityLogFile {
            XCActivityLogFile(
                path: path,
                timeStoppedRecording: timeStoppedRecording,
                signature: signature
            )
        }
    }
#endif
