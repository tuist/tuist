import AnyCodable
import Foundation
@testable import TuistAnalytics

extension CommandEvent {
    static func test(
        name: String = "generate",
        subcommand: String? = nil,
        params: [String: AnyCodable] = [:],
        commandArguments: [String] = [],
        durationInMs: Int = 20,
        clientId: String = "123",
        tuistVersion: String = "1.2.3",
        swiftVersion: String = "5.2",
        macOSVersion: String = "10.15",
        machineHardwareName: String = "arm64"
    ) -> CommandEvent {
        CommandEvent(
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
            isCI: false
        )
    }
}
