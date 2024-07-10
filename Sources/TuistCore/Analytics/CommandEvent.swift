import AnyCodable
import Foundation
import Path

/// A `CommandEvent` is the analytics event to track the execution of a Tuist command
public struct CommandEvent: Codable, Equatable, AsyncQueueEvent {
    public let runId: String
    public let name: String
    public let subcommand: String?
    public let params: [String: AnyCodable]
    public let commandArguments: [String]
    public let durationInMs: Int
    public let clientId: String
    public let tuistVersion: String
    public let swiftVersion: String
    public let macOSVersion: String
    public let machineHardwareName: String
    public let isCI: Bool
    public let status: Status

    public enum Status: Codable, Equatable {
        case success, failure(String)
    }

    public let id = UUID()
    public let date = Date()
    public let dispatcherId = "TuistAnalytics"

    private enum CodingKeys: String, CodingKey {
        case runId
        case name
        case subcommand
        case params
        case commandArguments
        case durationInMs = "duration"
        case clientId
        case tuistVersion
        case swiftVersion
        case macOSVersion = "macos_version"
        case machineHardwareName
        case isCI
        case status
    }

    public init(
        runId: String,
        name: String,
        subcommand: String?,
        params: [String: AnyCodable],
        commandArguments: [String],
        durationInMs: Int,
        clientId: String,
        tuistVersion: String,
        swiftVersion: String,
        macOSVersion: String,
        machineHardwareName: String,
        isCI: Bool,
        status: Status
    ) {
        self.runId = runId
        self.name = name
        self.subcommand = subcommand
        self.params = params
        self.commandArguments = commandArguments
        self.durationInMs = durationInMs
        self.clientId = clientId
        self.tuistVersion = tuistVersion
        self.swiftVersion = swiftVersion
        self.macOSVersion = macOSVersion
        self.machineHardwareName = machineHardwareName
        self.isCI = isCI
        self.status = status
    }
}

#if MOCKING
    extension CommandEvent {
        public static func test(
            runId: String = "",
            name: String = "generate",
            subcommand: String? = nil,
            params: [String: AnyCodable] = [:],
            commandArguments: [String] = [],
            durationInMs: Int = 20,
            clientId: String = "123",
            tuistVersion: String = "1.2.3",
            swiftVersion: String = "5.2",
            macOSVersion: String = "10.15",
            machineHardwareName: String = "arm64",
            status: Status = .success
        ) -> CommandEvent {
            CommandEvent(
                runId: runId,
                name: name,
                subcommand: subcommand,
                params: params,
                commandArguments: commandArguments,
                durationInMs: durationInMs,
                clientId: clientId,
                tuistVersion: tuistVersion,
                swiftVersion: swiftVersion,
                macOSVersion: macOSVersion,
                machineHardwareName: machineHardwareName,
                isCI: false,
                status: status
            )
        }
    }
#endif
