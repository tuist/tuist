import Command
import Mockable

@Mockable
public protocol SecurityControlling {
    func addInternetPassword(
        accountName: String,
        serverName: String,
        password: String?,
        securityProtocol: SecurityProtocol?,
        update: Bool,
        applications: [String]
    ) async throws
}

public enum SecurityProtocol: String {
    case https = "htps"
}

public struct SecurityController: SecurityControlling {
    private let commandRunner: CommandRunning

    public init(
        commandRunner: CommandRunning = CommandRunner()
    ) {
        self.commandRunner = commandRunner
    }

    public func addInternetPassword(
        accountName: String,
        serverName: String,
        password: String?,
        securityProtocol: SecurityProtocol?,
        update: Bool,
        applications: [String]
    ) async throws {
        var arguments = [
            "/usr/bin/security",
            "add-internet-password",
            "-a", accountName,
            "-s", serverName,
        ]

        if let password {
            arguments.append(
                contentsOf: [
                    "-w", password,
                ]
            )
        }

        if let securityProtocol {
            arguments.append(
                contentsOf: [
                    "-r", securityProtocol.rawValue,
                ]
            )
        }

        if update {
            arguments.append("-U")
        }

        arguments.append(contentsOf: applications.flatMap { ["-T", $0] })

        _ = try await commandRunner.run(
            arguments: arguments
        )
        .concatenatedString()
    }
}
