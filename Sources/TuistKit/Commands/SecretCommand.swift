import ArgumentParser
import Foundation
import Signals
import TSCBasic
import TuistGenerator
import TuistSupport

struct SecretCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "secret",
                             abstract: "Generates a secret key")
    }

    func run() throws {
        try SecretService().run()
    }
}
