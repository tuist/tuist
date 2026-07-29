import ArgumentParser
import SwifterPMCore

do {
    var command = try SwifterPMCommand.parse(
        DeprecatedSwiftPMOptions.strip(Array(CommandLine.arguments.dropFirst()))
    )
    try await command.runAsync()
} catch {
    SwifterPMCommand.exit(withError: error)
}
