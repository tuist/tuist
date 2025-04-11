import Foundation

struct ActivityLog: Codable {
    let fileName: String
    let timeStartedRecording: Double
    let timeStoppedRecording: Double
    let schemeIdentifierSchemeName: String

    enum CodingKeys: String, CodingKey {
        case fileName
        case timeStartedRecording
        case timeStoppedRecording
        case schemeIdentifierSchemeName = "schemeIdentifier-schemeName"
    }
}
