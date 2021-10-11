import ArgumentParser
import Foundation
import TSCBasic
import TuistLoader
import TuistSupport

struct DumpCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "dump",
            abstract: "Outputs the manifest as a JSON"
        )
    }

    // MARK: - Attributes

    @Option(
        name: .shortAndLong,
        help: "The path to the folder where the manifest is",
        completion: .directory
    )
    var path: String?

    @Argument(help: "The manifest to be dumped")
    var manifest: DumpableManifest = .project

    func run() throws {
        try DumpService().run(path: path, manifest: manifest)
    }
}

extension DumpableManifest: ExpressibleByArgument {}
