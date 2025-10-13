import ArgumentParser
import Foundation
import Path
import TuistAutomation
import TuistCache
import TuistCore
import TuistHasher
import TuistServer
import TuistSupport
import XcodeGraph

struct XcodeBuildCommandReorderer: AsyncParsableCommand {
    @Argument(
        parsing: .allUnrecognized,
        help: "Arguments for xcodebuild. Can be used as fallback when subcommands are not first. Example: tuist xcodebuild -workspace MyApp.xcworkspace build -scheme MyApp"
    )
    var arguments: [String] = []

    func run() async throws {
        guard !arguments.isEmpty else {
            throw ValidationError("No arguments provided. Use 'tuist xcodebuild --help' for usage information.")
        }

        let validActions = XcodeBuildCommand.configuration.subcommands.compactMap { command in
            command.configuration.commandName
        }

        guard let actionIndex = arguments.firstIndex(where: { validActions.contains($0) }) else {
            throw ValidationError("No valid action found. Valid actions are: \(validActions.joined(separator: ", "))")
        }

        let action = arguments[actionIndex]

        let preActionArgs = Array(arguments[..<actionIndex])
        let postActionArgs = actionIndex + 1 < arguments.count ? Array(arguments[(actionIndex + 1)...]) : []

        let reorderedArgs = [action] + preActionArgs + postActionArgs

        guard reorderedArgs != arguments else {
            throw ValidationError("Unable to reorder arguments to match subcommand format.")
        }

        guard var parsedCommand = try XcodeBuildCommand.parseAsRoot(reorderedArgs) as? AsyncParsableCommand else {
            throw ValidationError("Command parsing failed.")
        }

        try await parsedCommand.run()
    }
}
