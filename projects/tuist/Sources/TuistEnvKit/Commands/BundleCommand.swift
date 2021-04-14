import ArgumentParser
import Foundation
import TSCBasic

struct BundleCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "bundle",
            abstract: "Bundles the version specified in the .tuist-version file into the .tuist-bin directory"
        )
    }

    func run() throws {
        try BundleService().run()
    }
}
