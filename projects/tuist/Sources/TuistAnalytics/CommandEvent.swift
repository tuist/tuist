import Foundation
import TuistCore

/// A `CommandEvent` is the analytics event to track the execution of a Tuist command
/// Stats are public and reported at https://stats.tuist.io/
public struct CommandEvent: Codable, Equatable, AsyncQueueEvent {
    public let name: String
    public let subcommand: String?
    public let params: [String: String]
    public let durationInMs: Int
    public let clientId: String
    public let tuistVersion: String
    public let swiftVersion: String
    public let macOSVersion: String
    public let machineHardwareName: String

    public let id: UUID = UUID()
    public let date = Date()
    public let dispatcherId = TuistAnalyticsDispatcher.dispatcherId

    private enum CodingKeys: String, CodingKey {
        case name
        case subcommand
        case params
        case durationInMs = "duration"
        case clientId
        case tuistVersion
        case swiftVersion
        case macOSVersion = "macos_version"
        case machineHardwareName
    }

    public init(
        name: String,
        subcommand: String?,
        params: [String: String],
        durationInMs: Int,
        clientId: String,
        tuistVersion: String,
        swiftVersion: String,
        macOSVersion: String,
        machineHardwareName: String
    ) {
        self.name = name
        self.subcommand = subcommand
        self.params = params
        self.durationInMs = durationInMs
        self.clientId = clientId
        self.tuistVersion = tuistVersion
        self.swiftVersion = swiftVersion
        self.macOSVersion = macOSVersion
        self.machineHardwareName = machineHardwareName
    }
}
