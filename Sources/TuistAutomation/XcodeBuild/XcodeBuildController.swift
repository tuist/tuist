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

    init(formatter: Formatting,
         environment: Environmenting)
    {
        self.formatter = formatter
        self.environment = environment
    }

    public func build(_ target: XcodeBuildTarget,
                      scheme: String,
                      clean: Bool = false,
                      arguments: [XcodeBuildArgument]) -> AsyncThrowingStream<SystemEvent<XcodeBuildOutput>, Error>
    {
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

        return run(command: command, isVerbose: environment.isVerbose)
    }

    public func test(
        _ target: XcodeBuildTarget,
        scheme: String,
        clean: Bool = false,
        destination: XcodeBuildDestination,
        derivedDataPath: AbsolutePath?,
        resultBundlePath: AbsolutePath?,
        arguments: [XcodeBuildArgument]
    ) -> AsyncThrowingStream<SystemEvent<XcodeBuildOutput>, Error> {
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

        // Destination
        switch destination {
        case let .device(udid):
            command.append(contentsOf: ["-destination", "id=\(udid)"])
        case .mac:
            break
        }

        // Derived data path
        if let derivedDataPath = derivedDataPath {
            command.append(contentsOf: ["-derivedDataPath", derivedDataPath.pathString])
        }

        // Result bundle path
        if let resultBundlePath = resultBundlePath {
            command.append(contentsOf: ["-resultBundlePath", resultBundlePath.pathString])
        }

        return run(command: command, isVerbose: environment.isVerbose)
    }

    public func archive(_ target: XcodeBuildTarget,
                        scheme: String,
                        clean: Bool,
                        archivePath: AbsolutePath,
                        arguments: [XcodeBuildArgument]) -> AsyncThrowingStream<SystemEvent<XcodeBuildOutput>, Error>
    {
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

        return run(command: command, isVerbose: environment.isVerbose)
    }

    public func createXCFramework(frameworks: [AbsolutePath],
                                  output: AbsolutePath) -> AsyncThrowingStream<SystemEvent<XcodeBuildOutput>, Error>
    {
        var command = ["/usr/bin/xcrun", "xcodebuild", "-create-xcframework"]
        command.append(contentsOf: frameworks.flatMap { ["-framework", $0.pathString] })
        command.append(contentsOf: ["-output", output.pathString])
        command.append("-allow-internal-distribution")
        return run(command: command, isVerbose: environment.isVerbose)
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
            .timeout(.seconds(20), scheduler: DispatchQueue.global())
            .retry(5)
            .values
        var buildSettingsByTargetName = [String: XcodeBuildSettings]()
        for try await string in values {
            var currentSettings: [String: String] = [:]
            var currentTarget: String?

            let flushTarget = { () -> Void in
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

    fileprivate func run(command: [String], isVerbose: Bool) -> AsyncThrowingStream<SystemEvent<XcodeBuildOutput>, Error> {
        if isVerbose {
            return System.shared.publisher(command).values
                .mapAsXcodeBuildOutput()
        } else {
            return System.shared.publisher(
                command,
                // swiftlint:disable:next force_try
                pipeTo: try! formatter.buildArguments()
            ).values.mapAsXcodeBuildOutput()
        }
    }
}

private AsyncThrowingStream where Element == SystemEvent<Data> {
    func mapAsXcodeBuildOutput() -> AsyncThrowingStream<SystemEvent<XcodeBuildOutput>, Error> {
        var iterator = makeAsyncIterator()
        var subIterator: IndexingIterator<[SystemEvent<XcodeBuildOutput>]>?
        return AsyncThrowingStream<SystemEvent<XcodeBuildOutput>, Error> {
            if let output = subIterator?.next() {
                return output
            }

            guard let event = try await iterator.next() else { return nil }
            switch event {
            case let .standardError(errorData):
                guard let line = String(data: errorData, encoding: .utf8) else { return nil }
                let output = line.split(separator: "\n").map { line -> SystemEvent<XcodeBuildOutput> in
                    SystemEvent.standardError(XcodeBuildOutput(raw: "\(String(line))\n"))
                }
                subIterator = output.makeIterator()
                return subIterator?.next()
            case let .standardOutput(outputData):
                guard let line = String(data: outputData, encoding: .utf8) else { return nil }
                let output = line.split(separator: "\n").map { line -> SystemEvent<XcodeBuildOutput> in
                    SystemEvent.standardOutput(XcodeBuildOutput(raw: "\(String(line))\n"))
                }
                subIterator = output.makeIterator()
                return subIterator?.next()
            }
        }
    }
}
