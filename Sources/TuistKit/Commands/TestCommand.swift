import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

/// Command that tests a target from the project in the current directory.
struct TestCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "test",
            abstract: "Tests a project"
        )
    }

    @Argument(
        help: "The scheme to be tested. By default it tests all the testable targets of the project in the current directory."
    )
    var scheme: String?

    @Flag(
        name: .shortAndLong,
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

    @Flag(
        name: .long,
        help: "When passed, it skips testing UI Tests targets."
    )
    var skipUITests: Bool = false

    @Option(
        name: [.long, .customShort("T")],
        help: "Path where test result bundle will be saved."
    )
    var resultBundlePath: String?
    
    @Option(
        name: .long,
        help: "Tests will run <number> of times."
    )
    var testIterations: Int?
    
    @Flag(
        name: .long,
        help: "Tests will retry on failure. May be used in conjunction with -test-iterations <number>, in which case <number> will be the maximum number of iterations. Otherwise, a maximum of 3 is assumed."
    )
    var retryTestsOnFailure: Bool = false

    func runAsync() async throws {
        let absolutePath: AbsolutePath

        if let path = path {
            absolutePath = AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            absolutePath = FileHandler.shared.currentPath
        }

        try await TestService().run(
            schemeName: scheme,
            clean: clean,
            configuration: configuration,
            path: absolutePath,
            deviceName: device,
            osVersion: os,
            skipUITests: skipUITests,
            resultBundlePath: resultBundlePath.map {
                AbsolutePath(
                    $0,
                    relativeTo: FileHandler.shared.currentPath
                )
            },
            testIterations: testIterations,
            retryTestsOnFailure: retryTestsOnFailure
        )
    }
}
