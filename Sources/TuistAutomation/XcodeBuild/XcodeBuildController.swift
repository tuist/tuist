import Foundation
import Path
import TuistCore
import TuistSupport
import Command
import XcodeGraph

public final class XcodeBuildController: XcodeBuildControlling {
    // MARK: - Attributes

    /// Matches lines of the forms:
    ///
    /// Build settings for action build and target "Tuist Mac":
    /// Build settings for action test and target TuistTests:
    private static let targetSettingsRegex = try! NSRegularExpression( // swiftlint:disable:this force_try
        pattern: "^Build settings for action (?:\\S+) and target \\\"?([^\":]+)\\\"?:$",
        options: [.caseInsensitive, .anchorsMatchLines]
    )

    private let formatter: Formatting
    private let simulatorController: SimulatorController
    private let system: Systeming
    private let commandRunner: CommandRunning

    public convenience init() {
        self.init(
            formatter: Formatter(),
            commandRunner: CommandRunner(),
            system: System.shared
        )
    }

    init(
        formatter: Formatting,
        commandRunner: CommandRunning,
        system: Systeming
    ) {
        self.formatter = formatter
        self.simulatorController = SimulatorController()
        self.system = system
        self.commandRunner = commandRunner
    }

    public func build(
        _ target: XcodeBuildTarget,
        scheme: String,
        destination: XcodeBuildDestination?,
        rosetta: Bool,
        derivedDataPath: AbsolutePath?,
        clean: Bool = false,
        arguments: [XcodeBuildArgument],
        passthroughXcodeBuildArguments: [String]
    ) async throws {
        let extraArguments = arguments.flatMap(\.arguments)
        var arguments: [String] = []

        // Action
        if clean {
            arguments.append("clean")
        }
        arguments.append("build")

        // Scheme
        arguments.append(contentsOf: ["-scheme", scheme])

        // Target
        arguments.append(contentsOf: target.xcodebuildArguments)

        // Arguments
        arguments.append(contentsOf: extraArguments)

        // Passthrough arguments
        arguments.append(contentsOf: passthroughXcodeBuildArguments)

        // Destination
        switch destination {
        case let .device(udid):
            var value = ["id=\(udid)"]
            if rosetta {
                value += ["arch=x86_64"]
            }
            arguments.append(contentsOf: ["-destination", value.joined(separator: ",")])
        case .mac:
            arguments.append(contentsOf: ["-destination", try await simulatorController.macOSDestination()])
        case .macCatalyst:
            arguments.append(contentsOf: ["-destination", try await simulatorController.macOSDestination(catalyst: true)])
        case nil:
            break
        }

        // Derived data path
        if let derivedDataPath {
            arguments.append(contentsOf: ["-derivedDataPath", derivedDataPath.pathString])
        }

        try await run(arguments: arguments)
    }

    public func test(
        _ target: XcodeBuildTarget,
        scheme: String,
        clean: Bool = false,
        destination: XcodeBuildDestination?,
        action: XcodeBuildTestAction,
        rosetta: Bool,
        derivedDataPath: AbsolutePath?,
        resultBundlePath: AbsolutePath?,
        arguments: [XcodeBuildArgument],
        retryCount: Int,
        testTargets: [TestIdentifier],
        skipTestTargets: [TestIdentifier],
        testPlanConfiguration: TestPlanConfiguration?,
        passthroughXcodeBuildArguments: [String]
    ) async throws {
        let extraArguments = arguments.flatMap(\.arguments)
        var arguments: [String] = []

        // Action
        if clean {
            arguments.append("clean")
        }
        
        switch action {
        case .test:
            arguments.append("test")
        case .build:
            arguments.append("build-for-testing")
        case .testWithoutBuilding:
            arguments.append("test-without-building")
        }

        // Scheme
        arguments.append(contentsOf: ["-scheme", scheme])

        // Target
        arguments.append(contentsOf: target.xcodebuildArguments)

        // Arguments
        arguments.append(contentsOf: extraArguments)

        // Passthrough arguments
        arguments.append(contentsOf: passthroughXcodeBuildArguments)
        
        // Retry On Failure
        if retryCount > 0 {
            arguments.append(contentsOf: XcodeBuildArgument.retryCount(retryCount).arguments)
        }

        // Destination
        switch destination {
        case let .device(udid):
            var value = ["id=\(udid)"]
            if rosetta {
                value += ["arch=x86_64"]
            }
            arguments.append(contentsOf: ["-destination", value.joined(separator: ",")])
        case .mac:
            arguments.append(contentsOf: ["-destination", try await simulatorController.macOSDestination()])
        case .macCatalyst:
            arguments.append(contentsOf: ["-destination", try await simulatorController.macOSDestination(catalyst: true)])
        case nil:
            break
        }

        // Derived data path
        if let derivedDataPath {
            arguments.append(contentsOf: ["-derivedDataPath", derivedDataPath.pathString])
        }

        // Result bundle path
        if let resultBundlePath {
            arguments.append(contentsOf: ["-resultBundlePath", resultBundlePath.pathString])
        }

        for test in testTargets {
            arguments.append(contentsOf: ["-only-testing", test.description])
        }

        for test in skipTestTargets {
            arguments.append(contentsOf: ["-skip-testing", test.description])
        }

        if let testPlanConfiguration {
            arguments.append(contentsOf: ["-testPlan", testPlanConfiguration.testPlan])
            for configuration in testPlanConfiguration.configurations {
                arguments.append(contentsOf: ["-only-test-configuration", configuration])
            }

            for configuration in testPlanConfiguration.skipConfigurations {
                arguments.append(contentsOf: ["-skip-test-configuration", configuration])
            }
        }

        try await run(arguments: arguments)
    }

    public func archive(
        _ target: XcodeBuildTarget,
        scheme: String,
        clean: Bool,
        archivePath: AbsolutePath,
        arguments: [XcodeBuildArgument],
        derivedDataPath: AbsolutePath?
    ) async throws {
        let extraArguments = arguments.flatMap(\.arguments)
        var arguments: [String] = []

        // Action
        if clean {
            arguments.append("clean")
        }
        arguments.append("archive")

        // Scheme
        arguments.append(contentsOf: ["-scheme", scheme])

        // Target
        arguments.append(contentsOf: target.xcodebuildArguments)

        // Archive path
        arguments.append(contentsOf: ["-archivePath", archivePath.pathString])

        // Derived data path
        if let derivedDataPath {
            arguments.append(contentsOf: ["-derivedDataPath", derivedDataPath.pathString])
        }

        // Arguments
        arguments.append(contentsOf: extraArguments)

        try await run(arguments: arguments)
    }

    public func createXCFramework(
        arguments: [String],
        output: AbsolutePath
    ) async throws {
        var arguments = ["-create-xcframework"] + arguments
        arguments.append(contentsOf: ["-output", output.pathString])
        arguments.append("-allow-internal-distribution")

        try await run(arguments: arguments)
    }

    enum ShowBuildSettingsError: Error {
        case timeout
    }

    public func showBuildSettings(
        _ target: XcodeBuildTarget,
        scheme: String,
        configuration: String,
        derivedDataPath: AbsolutePath?
    ) async throws -> [String: XcodeBuildSettings] {
        var command = ["/usr/bin/xcrun", "xcodebuild", "archive", "-showBuildSettings", "-skipUnavailableActions"]

        // Configuration
        command.append(contentsOf: ["-configuration", configuration])

        // Scheme
        command.append(contentsOf: ["-scheme", scheme])

        // Derived data path
        if let derivedDataPath {
            command.append(contentsOf: ["-derivedDataPath", derivedDataPath.pathString])
        }

        // Target
        command.append(contentsOf: target.xcodebuildArguments)
        
        let buildSettings = try await loadBuildSettings(command)
        
        var buildSettingsByTargetName = [String: XcodeBuildSettings]()
        var currentSettings: [String: String] = [:]
        var currentTarget: String?
        
        func flushTarget() {
            if let currentTarget {
                let buildSettings = XcodeBuildSettings(
                    currentSettings,
                    target: currentTarget,
                    configuration: configuration
                )
                buildSettingsByTargetName[buildSettings.target] = buildSettings
            }
            
            currentTarget = nil
            currentSettings = [:]
        }

        buildSettings.enumerateLines { line, _ in
            if let result = XcodeBuildController.targetSettingsRegex.firstMatch(
                in: line,
                range: NSRange(line.startIndex..., in: line)
            ) {
                let targetRange = Range(result.range(at: 1), in: line)!
                
                flushTarget()
                currentTarget = String(line[targetRange])
                return
            }
            
            let trimSet = CharacterSet.whitespacesAndNewlines
            let components = line
                .split(maxSplits: 1) { $0 == "=" }
                .map { $0.trimmingCharacters(in: trimSet) }
            
            if components.count == 2 {
                currentSettings[components[0]] = components[1]
            }
        }
        
        flushTarget()
        
        return buildSettingsByTargetName
    }

    public func run(arguments: [String]) async throws {
        let logger = Logger.current
        
        func format(_ bytes: [UInt8]) -> String {
            let string = String(decoding: bytes, as: Unicode.UTF8.self)
            if Environment.current.isVerbose == true {
                return string
            } else {
                return self.format(string)
            }
        }
        
        func log(_ bytes: [UInt8], isError: Bool = false) {
            let lines = format(bytes).split(separator: "\n")
            for line in lines where !line.isEmpty {
                if isError {
                    logger.error("\(line)")
                } else {
                    logger.info("\(line)")
                }
            }
        }
        
        let command = ["/usr/bin/xcrun", "xcodebuild"] + arguments
        
        logger.debug("Running xcodebuild command: \(command.joined(separator: " "))")
        
        try system.run(command,
                       verbose: false,
                       environment: Environment.current.variables,
                       redirection: .stream(stdout: { bytes in
            log(bytes)
        }, stderr: { bytes in
            log(bytes, isError: true)
        }))
    }
    
    public func version() async throws -> Version? {
        let output = try await commandRunner
            .run(arguments: ["xcodebuild", "-version"])
            .concatenatedString()
       let components = output
            .components(separatedBy: .whitespacesAndNewlines)
        
        guard
            let xcodeIndex = components.firstIndex(of: "Xcode"),
            xcodeIndex + 1 < components.endIndex
        else { return nil }
        
        return Version(string: components[xcodeIndex + 1])
    }
    
    private func loadBuildSettings(_ command: [String]) async throws -> String {
        // xcodebuild has a bug where xcodebuild -showBuildSettings
        // can sometimes hang indefinitely on projects that don't
        // share any schemes, so automatically bail out if it looks
        // like that's happening.
        return try await Task.retrying(maxRetryCount: 5) {
            let systemTask = Task {
                return try await self.system.runAndCollectOutput(command).standardOutput
            }
            
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: 20_000_000)
                systemTask.cancel()
            }
            
            let result = try await systemTask.value
            timeoutTask.cancel()
            return result
        }.value
    }
}

// MARK: - Helpers

fileprivate extension XcodeBuildController {
    func format(_ multiLineText: String) -> String {
        multiLineText.split(separator: "\n").map {
            let line = String($0)
            let formattedLine = formatter.format(line)

            return formattedLine ?? ""
        }
        .joined(separator: "\n")
    }
}
