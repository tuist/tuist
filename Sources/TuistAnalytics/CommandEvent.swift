import Foundation

/// A `CommandEvent` is the analytics event to track the execution of a Tuist command
/// Stats are public and reported at https://stats.tuist.io/
public struct CommandEvent: Codable {
    public init(
        name: String,
        subcommand: String?,
        params: [String: String],
        duration: TimeInterval,
        clientId: String,
        tuistVersion: String,
        swiftVersion: String,
        macOSVersion: String,
        machineHardwareName: String
    ) {
        self.name = name
        self.subcommand = subcommand
        self.params = params
        self.duration = duration
        self.clientId = clientId
        self.tuistVersion = tuistVersion
        self.swiftVersion = swiftVersion
        self.macOSVersion = macOSVersion
        self.machineHardwareName = machineHardwareName
    }

    let name: String
    let subcommand: String?
    let params: [String: String]
    let duration: TimeInterval

    let clientId: String
    let tuistVersion: String
    let swiftVersion: String
    let macOSVersion: String
    let machineHardwareName: String
}
