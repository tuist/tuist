import ArgumentParser
import Foundation
import TSCBasic
import TuistCore
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
        help: "Tests will retry <number> of times until success. Example: if 1 is specified, the test will be retried at most once, hence it will run up to 2 times."
    )
    var retryCount: Int = 0

    @Option(
        name: .long,
        help: "The test plan to run."
    )
    var testPlan: String?

    @Option(
        name: .long,
        parsing: .upToNextOption,
        help: "The list of test identifiers you want to test. Expected format is TestTarget[/TestClass[/TestMethod]]. It is applied before --skip-testing",
        transform: TestIdentifier.init(string:)
    )
    var testTargets: [TestIdentifier] = []

    @Option(
        name: .long,
        parsing: .upToNextOption,
        help: "The list of test identifiers you want to skip testing. Expected format is TestTarget[/TestClass[/TestMethod]].",
        transform: TestIdentifier.init(string:)
    )
    var skipTestTargets: [TestIdentifier] = []

    @Option(
        name: .long,
        parsing: .upToNextOption,
        help: "The list of configurations you want to test. It is applied before --skip-test-configuration"
    )
    var testConfigurations: [String] = []

    @Option(
        name: .long,
        parsing: .upToNextOption,
        help: "The list of configurations you want to skip testing."
    )
    var skipTestConfigurations: [String] = []

    func validate() throws {
        let targetsIntersection = Set(testTargets)
            .intersection(skipTestTargets)
        if !targetsIntersection.isEmpty {
            throw ValidationError.duplicatedTestTargets(targetsIntersection)
        }
        if !testTargets.isEmpty {
            // --test-targets Test --skip-test-targets AnotherTest
            let skipTestTargetsOnly = Set(skipTestTargets.map { TestIdentifier(target: $0.target) })
            let testTargetsOnly = testTargets.map { TestIdentifier(target: $0.target) }
            let targetsOnlyIntersection = skipTestTargetsOnly.intersection(testTargetsOnly)
            if targetsOnlyIntersection.isEmpty {
                throw ValidationError.nothingToSkip(skipped: skipTestTargets.filter { skipTarget in !testTargetsOnly.contains(TestIdentifier(target: skipTarget.target)) }, included: testTargets)
            }

            // --test-targets Test/MyTest --skip-test-targets Test/AnotherTest
            let skipTestTargetsClasses = Set(skipTestTargets.map { TestIdentifier(target: $0.target, class: $0.class) })
            let testTargetsClasses = testTargets.map { TestIdentifier(target: $0.target, class: $0.class) }
            let targetsClassesIntersection = skipTestTargetsClasses.intersection(testTargetsClasses)
                .intersection(testTargetsClasses.map { TestIdentifier(target: $0.target, class: $0.class) })
            if targetsClassesIntersection.isEmpty {
                throw ValidationError.nothingToSkip(skipped: skipTestTargets.filter { skipTarget in !testTargetsClasses.contains { $0 == TestIdentifier(target: skipTarget.target, class: skipTarget.class) } }, included: testTargets)
            }
        }
    }

    func run() async throws {
        let absolutePath: AbsolutePath

        if let path = path {
            absolutePath = try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
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
                try AbsolutePath(
                    validating: $0,
                    relativeTo: FileHandler.shared.currentPath
                )
            },
            retryCount: retryCount,
            testTargets: testTargets,
            skipTestTargets: skipTestTargets,
            testPlanConfiguration: testPlan.map { testPlan in
                TestPlanConfiguration(
                    testPlan: testPlan,
                    testConfigurations: testConfigurations,
                    skipTestConfigurations: skipTestConfigurations
                )
            }
        )
    }

    enum ValidationError: LocalizedError {
        case duplicatedTestTargets(Set<TestIdentifier>)
        case nothingToSkip(skipped: [TestIdentifier], included: [TestIdentifier])

        var errorDescription: String? {
            switch self {
            case .duplicatedTestTargets(let targets):
                return "The target identifier cannot be specified both in --test-targets and --skip-test-targets (were specified: \(targets.map(\.description).joined(separator: ", ")))"
            case .nothingToSkip(let skippedTargets, let includedTargets):
                return "Some of the targets specified in --skip-test-targets (\(skippedTargets.map(\.description).joined(separator: ", "))) will always be skipped as they are not included in the targets specified (\(includedTargets.map(\.description).joined(separator: ", ")))"
            }
        }
    }
}
