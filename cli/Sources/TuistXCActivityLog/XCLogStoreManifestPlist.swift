import Foundation

public struct XCLogStoreManifestPlist: Codable {
    public struct ActivityLog: Codable {
        public let fileName: String
        public let timeStartedRecording: Double
        public let timeStoppedRecording: Double
        public let signature: String

        enum CodingKeys: String, CodingKey {
            case fileName
            case timeStartedRecording
            case timeStoppedRecording
            case signature
        }

        public init(
            fileName: String,
            timeStartedRecording: Double,
            timeStoppedRecording: Double,
            signature: String
        ) {
            self.fileName = fileName
            self.timeStartedRecording = timeStartedRecording
            self.timeStoppedRecording = timeStoppedRecording
            self.signature = signature
        }
    }

    public let logs: [String: Self.ActivityLog]

    public init(logs: [String: Self.ActivityLog]) {
        self.logs = logs
    }
}
