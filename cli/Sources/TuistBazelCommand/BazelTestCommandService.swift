import Command
import FileSystem
import Foundation
import Noora
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistServer
import TuistSupport

public struct BazelTestCommandService {
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let listTestCasesService: ListTestCasesServicing
    private let commandRunner: CommandRunning

    public init(
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        listTestCasesService: ListTestCasesServicing = ListTestCasesService(),
        commandRunner: CommandRunning = CommandRunner()
    ) {
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.listTestCasesService = listTestCasesService
        self.commandRunner = commandRunner
    }

    public func run(
        directory: String?,
        bazel: String,
        arguments: [String],
        quarantine: Bool
    ) async throws {
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(directory)
        var arguments = arguments

        var muted = Set<BazelTestCaseIdentity>()
        if quarantine {
            let policies = try await quarantinePolicies(directory: directoryPath)
            muted = policies.muted
            let targets = policies.skipped
            arguments = try Self.excluding(targets, from: arguments)
            if !targets.isEmpty {
                Noora.current.passthrough(
                    "Skipping \(targets.count) Bazel target(s) containing skipped tests. All cases in those targets are excluded."
                )
            }
        }

        if muted.isEmpty {
            try await runBazel(bazel, arguments: arguments, directory: directoryPath)
        } else {
            let arguments = arguments
            let muted = muted
            let commandRunner = commandRunner
            try await FileSystem().runInTemporaryDirectory(prefix: "bazel-quarantine") { temporaryDirectory in
                let eventsURL = URL(fileURLWithPath: temporaryDirectory.appending(component: "events.json").pathString)
                let separator = arguments.firstIndex(of: "--") ?? arguments.endIndex
                guard !arguments[..<separator].contains(where: {
                    $0 == "--build_event_json_file" || $0.hasPrefix("--build_event_json_file=")
                }) else { throw BazelTestCommandServiceError.buildEventFile }
                var recordedArguments = arguments
                recordedArguments.insert(contentsOf: [
                    "--build_event_json_file=\(eventsURL.path)",
                    "--nobuild_event_json_file_path_conversion",
                ], at: separator)
                do {
                    try await commandRunner.runAndPrint(
                        arguments: ["/usr/bin/env", bazel, "test"] + recordedArguments,
                        workingDirectory: directoryPath
                    )
                } catch let error as CommandError {
                    guard case .terminated(3, _, _) = error,
                          BazelTestFailureReader().onlyMutedTestsFailed(eventsURL: eventsURL, muted: muted)
                    else { throw error }
                    Noora.current.passthrough("Only muted test cases failed. Bazel's test reports retain their failures.")
                }
            }
        }
    }

    private func runBazel(_ bazel: String, arguments: [String], directory: AbsolutePath) async throws {
        try await commandRunner.runAndPrint(arguments: ["/usr/bin/env", bazel, "test"] + arguments, workingDirectory: directory)
    }

    private func quarantinePolicies(directory: AbsolutePath) async throws
        -> (skipped: [String], muted: Set<BazelTestCaseIdentity>)
    {
        let config = try await configLoader.loadConfig(path: directory)
        guard let fullHandle = config.fullHandle else {
            throw BazelSetupCommandServiceError.missingFullHandle
        }
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
        var targets = Set<String>()
        var muted = Set<BazelTestCaseIdentity>()
        var page = 1
        var count = 0

        while true {
            let response = try await listTestCasesService.listTestCases(
                fullHandle: fullHandle,
                serverURL: serverURL,
                flaky: nil,
                quarantined: true,
                state: nil,
                page: page,
                pageSize: 500
            )
            count += response.test_cases.count
            guard count <= 20000, page <= 40 else { throw BazelTestCommandServiceError.tooManyTests }
            for testCase in response.test_cases {
                if testCase.state == "skipped" {
                    targets.insert(testCase.module.name)
                } else if testCase.state == "muted" {
                    muted.insert(BazelTestCaseIdentity(
                        target: testCase.module.name,
                        suite: testCase.suite?.name ?? "",
                        name: testCase.name
                    ))
                }
            }
            guard page < (response.pagination_metadata.total_pages ?? page) else { break }
            page += 1
        }

        return (targets.sorted(), muted)
    }

    static func excluding(_ targets: [String], from arguments: [String]) throws -> [String] {
        guard !targets.isEmpty else { return arguments }
        guard targets.reduce(0, { $0 + $1.utf8.count + 4 }) < 100_000 else {
            throw BazelTestCommandServiceError.tooManyTests
        }
        let separator = arguments.firstIndex(of: "--") ?? arguments.endIndex
        let options = arguments[..<separator]
        guard !options.contains(where: { $0 == "--target_pattern_file" || $0.hasPrefix("--target_pattern_file=") }) else {
            throw BazelTestCommandServiceError.targetPatternFile
        }
        for target in targets {
            guard target.range(of: #"^(?:@@?[^/\s]*)?//[^:\s]*:[^:\s]+\z"#, options: .regularExpression) != nil,
                  !target.contains("..."),
                  !target.hasSuffix(":all"),
                  !target.hasSuffix(":*"),
                  !target.hasSuffix(":all-targets")
            else {
                throw BazelTestCommandServiceError.invalidTarget(target)
            }
        }
        let patterns = separator < arguments.endIndex ? Array(arguments[(separator + 1)...]) : []
        return Array(options) + ["--expand_test_suites", "--target_pattern_file=", "--"] + patterns + targets.map { "-\($0)" }
    }
}

enum BazelTestCommandServiceError: LocalizedError, Equatable {
    case targetPatternFile
    case invalidTarget(String)
    case buildEventFile
    case tooManyTests

    var errorDescription: String? {
        switch self {
        case .targetPatternFile:
            return "Pass target patterns directly when skipping quarantined Bazel tests. --target_pattern_file overrides exclusions."
        case let .invalidTarget(target):
            return "The skipped test target '\(target)' is not an explicit Bazel target label."
        case .buildEventFile:
            return "Tuist needs its own build event file to verify muted failures. Remove --build_event_json_file or use --no-quarantine."
        case .tooManyTests:
            return "The Bazel quarantine policy is too large to apply completely. Use --no-quarantine to run all requested tests."
        }
    }
}
