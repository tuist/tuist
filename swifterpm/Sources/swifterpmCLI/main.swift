import ArgumentParser
import SwifterPMCore

do {
    var command = try SwifterPMCommand.parse()
    try await command.runAsync()
} catch {
    SwifterPMCommand.exit(withError: error)
}
