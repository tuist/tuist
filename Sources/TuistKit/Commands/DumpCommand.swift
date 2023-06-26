import ArgumentParser
import Foundation
import TSCBasic
import TuistLoader
import TuistSupport

public struct DumpCommand: AsyncParsableCommand {
    public static var configuration: CommandConfiguration {
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
    public var path: String?

    @Argument(help: "The manifest to be dumped")
    public var manifest: DumpableManifest = .project
    
    // MARK: - Init
    
    public init() {}
    
    // MARK: - AsyncParsableCommand

    public func run() async throws {
        try await DumpService().run(path: path, manifest: manifest)
    }
}

extension DumpableManifest: ExpressibleByArgument {}
