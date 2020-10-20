import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

/// Command that tests a target from the project in the current directory.
struct TestCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "test",
                             abstract: "Tests a project")
    }

    @Argument(
        help: "The scheme to be tested. By default it tests all the testable targets of the project in the current directory."
    )
    var scheme: String?

    @Flag(
        help: "Force the generation of the project before testing."
    )
    var generate: Bool = false

    @Flag(
        help: "When passed, it cleans the project before testing it."
    )
    var clean: Bool = false

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project to be tested."
    )
    var path: String?
    
    @Option(
        name: .shortAndLong,
        help: "Test on a specific device."
    )
    var device: String?
    
    @Option(
        name: .shortAndLong,
        help: "Test with a specific version of the OS."
    )
    var osVersion: String?

    @Option(
        name: [.long, .customShort("C")],
        help: "The configuration to be used when testing the scheme."
    )
    var configuration: String?

    func run() throws {
        let absolutePath: AbsolutePath
        if let path = path {
            absolutePath = AbsolutePath(path)
        } else {
            absolutePath = FileHandler.shared.currentPath
        }
        try TestService().run(
            schemeName: scheme,
            generate: generate,
            clean: clean,
            configuration: configuration,
            path: absolutePath,
            deviceName: device,
            osVersion: osVersion
        )
    }
}
