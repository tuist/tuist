import Foundation
import TuistCore

/// A `CommandEvent` is the analytics event to track the execution of a Tuist command
/// Stats are public and reported at https://stats.tuist.io/
public struct CommandEvent: Codable, Equatable, AsyncQueueEvent {
    public let name: String
    public let subcommand: String?
    public let params: [String: String]
    public let duration: Int
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
        case duration
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
        duration: Int,
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
}
