import Combine
import Foundation
import TSCBasic
import TuistCore
import TuistSupport

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
    private let environment: Environmenting

    public convenience init() {
        self.init(
            formatter: Formatter(),
            environment: Environment.shared
        )
    }

    init(
        formatter: Formatting,
        environment: Environmenting
    ) {
        self.formatter = formatter
        self.environment = environment
    }

    public func build(
        _ target: XcodeBuildTarget,
        scheme: String,
        destination: XcodeBuildDestination?,
        rosetta: Bool,
        clean: Bool = false,
        arguments: [XcodeBuildArgument]
    ) throws -> AsyncThrowingStream<SystemEvent<XcodeBuildOutput>, Error> {
        var command = ["/usr/bin/xcrun", "xcodebuild"]

        // Action
        if clean {
            command.append("clean")
        }
        command.append("build")

        // Scheme
        command.append(contentsOf: ["-scheme", scheme])

        // Target
        command.append(contentsOf: target.xcodebuildArguments)

        // Arguments
        command.append(contentsOf: arguments.flatMap(\.arguments))

        // Destination
        switch destination {
        case let .device(udid):
            var value = ["id=\(udid)"]
            if rosetta {
                value += ["arch=x86_64"]
            }
            command.append(contentsOf: ["-destination", value.joined(separator: ",")])
        case .mac:
            command.append(contentsOf: ["-destination", SimulatorController().macOSDestination()])
        case nil:
            break
        }

        return try run(command: command, isVerbose: environment.isVerbose)
    }

    public func test(
        _ target: XcodeBuildTarget,
        scheme: String,
        clean: Bool = false,
        destination: XcodeBuildDestination,
        rosetta: Bool,
        derivedDataPath: AbsolutePath?,
        resultBundlePath: AbsolutePath?,
        arguments: [XcodeBuildArgument],
        retryCount: Int,
        testTargets: [TestIdentifier],
        skipTestTargets: [TestIdentifier],
        testPlanConfiguration: TestPlanConfiguration?
    ) throws -> AsyncThrowingStream<SystemEvent<XcodeBuildOutput>, Error> {
        var command = ["/usr/bin/xcrun", "xcodebuild"]

        // Action
        if clean {
            command.append("clean")
        }
        command.append("test")

        // Scheme
        command.append(contentsOf: ["-scheme", scheme])

        // Target
        command.append(contentsOf: target.xcodebuildArguments)

        // Arguments
        command.append(contentsOf: arguments.flatMap(\.arguments))

        // Retry On Failure
        if retryCount > 0 {
            command.append(contentsOf: XcodeBuildArgument.retryCount(retryCount).arguments)
        }

        // Destination
        switch destination {
        case let .device(udid):
            var value = ["id=\(udid)"]
            if rosetta {
                value += ["arch=x86_64"]
            }
            command.append(contentsOf: ["-destination", value.joined(separator: ",")])
        case .mac:
            command.append(contentsOf: ["-destination", SimulatorController().macOSDestination()])
        }

        // Derived data path
        if let derivedDataPath = derivedDataPath {
            command.append(contentsOf: ["-derivedDataPath", derivedDataPath.pathString])
        }

        // Result bundle path
        if let resultBundlePath = resultBundlePath {
            command.append(contentsOf: ["-resultBundlePath", resultBundlePath.pathString])
        }

        for test in testTargets {
            command.append(contentsOf: ["-only-testing", test.description])
        }

        for test in skipTestTargets {
            command.append(contentsOf: ["-skip-testing", test.description])
        }

        if let testPlanConfiguration {
            command.append(contentsOf: ["-testPlan", testPlanConfiguration.testPlan])
            for configuration in testPlanConfiguration.configurations {
                command.append(contentsOf: ["-only-test-configuration", configuration])
            }

            for configuration in testPlanConfiguration.skipConfigurations {
                command.append(contentsOf: ["-skip-test-configuration", configuration])
            }
        }

        return try run(command: command, isVerbose: environment.isVerbose)
    }

    public func archive(
        _ target: XcodeBuildTarget,
        scheme: String,
        clean: Bool,
        archivePath: AbsolutePath,
        arguments: [XcodeBuildArgument]
    ) throws -> AsyncThrowingStream<SystemEvent<XcodeBuildOutput>, Error> {
        var command = ["/usr/bin/xcrun", "xcodebuild"]

        // Action
        if clean {
            command.append("clean")
        }
        command.append("archive")

        // Scheme
        command.append(contentsOf: ["-scheme", scheme])

        // Target
        command.append(contentsOf: target.xcodebuildArguments)

        // Archive path
        command.append(contentsOf: ["-archivePath", archivePath.pathString])

        // Arguments
        command.append(contentsOf: arguments.flatMap(\.arguments))

        return try run(command: command, isVerbose: environment.isVerbose)
    }

    public func createXCFramework(
        frameworks: [AbsolutePath],
        output: AbsolutePath
    ) throws -> AsyncThrowingStream<SystemEvent<XcodeBuildOutput>, Error> {
        var command = ["/usr/bin/xcrun", "xcodebuild", "-create-xcframework"]
        command.append(contentsOf: frameworks.flatMap {
            let pathString = $0.pathString
            return [
                "-framework",
                // It's workaround for Xcode 15 RC bug
                // remove it since bug will be fixed
                // more details here: https://github.com/tuist/tuist/issues/5354
                pathString.hasPrefix("/var/") ? pathString.replacingOccurrences(of: "/var/", with: "/private/var/") : pathString
            ]
        })
        command.append(contentsOf: ["-output", output.pathString])
        command.append("-allow-internal-distribution")
        return try run(command: command, isVerbose: environment.isVerbose)
    }

    enum ShowBuildSettingsError: Error {
        // swiftformat:disable trailingCommas
        case timeout
    }

    public func showBuildSettings(
        _ target: XcodeBuildTarget,
        scheme: String,
        configuration: String
    ) async throws -> [String: XcodeBuildSettings] {
        var command = ["/usr/bin/xcrun", "xcodebuild", "archive", "-showBuildSettings", "-skipUnavailableActions"]

        // Configuration
        command.append(contentsOf: ["-configuration", configuration])

        // Scheme
        command.append(contentsOf: ["-scheme", scheme])

        // Target
        command.append(contentsOf: target.xcodebuildArguments)

        let values = System.shared.publisher(command)
            .mapToString()
            .collectAndMergeOutput()
            // xcodebuild has a bug where xcodebuild -showBuildSettings
            // can sometimes hang indefinitely on projects that don't
            // share any schemes, so automatically bail out if it looks
            // like that's happening.
            .timeout(.seconds(20), scheduler: DispatchQueue.main, customError: { ShowBuildSettingsError.timeout })
            .retry(5)
            .values
        var buildSettingsByTargetName = [String: XcodeBuildSettings]()
        for try await string in values {
            var currentSettings: [String: String] = [:]
            var currentTarget: String?

            let flushTarget = { () in
                if let currentTarget = currentTarget {
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

            string.enumerateLines { line, _ in
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
        }
        return buildSettingsByTargetName
    }

    fileprivate func run(command: [String], isVerbose: Bool) throws -> AsyncThrowingStream<SystemEvent<XcodeBuildOutput>, Error> {
        try run(command: command, isVerbose: isVerbose)
            .mapAsXcodeBuildOutput()
            .stream
    }

    fileprivate func run(command: [String], isVerbose: Bool) throws -> AnyPublisher<SystemEvent<Data>, Error> {
        if isVerbose {
            return System.shared.publisher(command)
        } else {
            let fomatterExecutable = try formatter.formatterExecutable()
            let compilationPublisher: AnyPublisher<SystemEvent<Data>, Error>? = if let compilation = fomatterExecutable.compilation {
                System.shared.publisher(compilation)
            } else {
                nil
            }
            if fomatterExecutable.compilation != nil {
                logger.debug("We've detected xcbeautify as sources so we'll compile it to use it with xcodebuild")
            }
            let xcodebuildPublisher = System.shared.publisher(command, pipeTo: fomatterExecutable.execution)
            
            if let compilationPublisher = compilationPublisher {
                return compilationPublisher.append(xcodebuildPublisher).eraseToAnyPublisher()
            } else {
                return xcodebuildPublisher
            }
        }
    }
}

extension Publisher where Output == SystemEvent<Data>, Failure == Error {
    fileprivate func mapAsXcodeBuildOutput() -> AnyPublisher<SystemEvent<XcodeBuildOutput>, Error> {
        compactMap { event -> SystemEvent<XcodeBuildOutput>? in
            switch event {
            case let .standardError(errorData):
                guard let line = String(data: errorData, encoding: .utf8) else { return nil }
                return SystemEvent.standardError(XcodeBuildOutput(raw: line))
            case let .standardOutput(outputData):
                guard let line = String(data: outputData, encoding: .utf8) else { return nil }
                return SystemEvent.standardOutput(XcodeBuildOutput(raw: line))
            }
        }.eraseToAnyPublisher()
    }
}
