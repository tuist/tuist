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
    var os: String?

    @Option(
        name: [.long, .customShort("C")],
        help: "The configuration to be used when testing the scheme."
    )
    var configuration: String?
    
    @Option(
        name: .shortAndLong,
        help: "Path where the automation project will be generated."
    )
    var automationPath: String?

    func run() throws {
        let absolutePath: AbsolutePath

        if let path = path {
            absolutePath = AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            absolutePath = FileHandler.shared.currentPath
        }

        try TestService().run(
            schemeName: scheme,
            clean: clean,
            configuration: configuration,
            path: absolutePath,
            automationPath: automationPath
                .map {
                    AbsolutePath($0, relativeTo: FileHandler.shared.currentPath)
                },
            deviceName: device,
            osVersion: os
        )
    }
}
