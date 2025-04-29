import Foundation

public struct ActivityLog: Codable {
    let fileName: String
    let timeStartedRecording: Double
    let timeStoppedRecording: Double

    enum CodingKeys: String, CodingKey {
        case fileName
        case timeStartedRecording
        case timeStoppedRecording
        case schemeIdentifierSchemeName = "schemeIdentifier-schemeName"
    }
}
