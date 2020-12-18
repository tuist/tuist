import Foundation

public struct CommandEvent: Codable {
    let name: String
    let subcommand: String?
    let duration: TimeInterval

    // SessionEnv
    let clientId: String
    let tuistVersion: String
    let swiftVersion: String
    let macOSVersion: String
}
