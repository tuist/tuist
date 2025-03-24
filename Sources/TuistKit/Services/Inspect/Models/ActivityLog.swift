import Foundation

struct ActivityLog: Codable {
    let fileName: String
    let timeStartedRecording: Double
    let timeStoppedRecording: Double
}
