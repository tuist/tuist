import Foundation

public struct XCLogStoreManifestPlist: Codable {
    public struct ActivityLog: Codable {
        public let fileName: String
        public let timeStartedRecording: Double
        public let timeStoppedRecording: Double

        enum CodingKeys: String, CodingKey {
            case fileName
            case timeStartedRecording
            case timeStoppedRecording
        }

        public init(fileName: String, timeStartedRecording: Double, timeStoppedRecording: Double) {
            self.fileName = fileName
            self.timeStartedRecording = timeStartedRecording
            self.timeStoppedRecording = timeStoppedRecording
        }
    }

    public let logs: [String: Self.ActivityLog]

    public init(logs: [String: Self.ActivityLog]) {
        self.logs = logs
    }
}
