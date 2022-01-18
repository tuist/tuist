import Foundation
import RxSwift
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
                      arguments: [XcodeBuildArgument]) -> Observable<SystemEvent<XcodeBuildOutput>>
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
    ) -> Observable<SystemEvent<XcodeBuildOutput>> {
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
                        arguments: [XcodeBuildArgument]) -> Observable<SystemEvent<XcodeBuildOutput>>
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

    public func createXCFramework(frameworks: [AbsolutePath], output: AbsolutePath) -> Observable<SystemEvent<XcodeBuildOutput>> {
        var command = ["/usr/bin/xcrun", "xcodebuild", "-create-xcframework"]
        command.append(contentsOf: frameworks.flatMap { ["-framework", $0.pathString] })
        command.append(contentsOf: ["-output", output.pathString])
        command.append("-allow-internal-distribution")
        return run(command: command, isVerbose: environment.isVerbose)
    }

    // swiftlint:disable:next function_body_length
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

        return try await System.shared.observable(command)
            .mapToString()
            .collectAndMergeOutput()
            // xcodebuild has a bug where xcodebuild -showBuildSettings
            // can sometimes hang indefinitely on projects that don't
            // share any schemes, so automatically bail out if it looks
            // like that's happening.
            .timeout(DispatchTimeInterval.seconds(20), scheduler: ConcurrentDispatchQueueScheduler(queue: .global()))
            .retry(5)
            .flatMap { string -> Observable<XcodeBuildSettings> in
                Observable.create { observer -> Disposable in
                    var currentSettings: [String: String] = [:]
                    var currentTarget: String?

                    let flushTarget = { () -> Void in
                        if let currentTarget = currentTarget {
                            let buildSettings = XcodeBuildSettings(
                                currentSettings,
                                target: currentTarget,
                                configuration: configuration
                            )
                            observer.onNext(buildSettings)
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
                    observer.onCompleted()
                    return Disposables.create()
                }
            }
            .reduce([String: XcodeBuildSettings](), accumulator: { acc, buildSettings -> [String: XcodeBuildSettings] in
                var acc = acc
                acc[buildSettings.target] = buildSettings
                return acc
            })
            .asSingle()
            .value
    }

    fileprivate func run(command: [String], isVerbose: Bool) -> Observable<SystemEvent<XcodeBuildOutput>> {
        if isVerbose {
            return run(command: command)
        } else {
            // swiftlint:disable:next force_try
            return run(command: command, pipedToArguments: try! formatter.buildArguments())
        }
    }

    fileprivate func run(command: [String]) -> Observable<SystemEvent<XcodeBuildOutput>> {
        System.shared.observable(command)
            .flatMap { event -> Observable<SystemEvent<XcodeBuildOutput>> in
                switch event {
                case let .standardError(errorData):
                    guard let line = String(data: errorData, encoding: .utf8) else { return Observable.empty() }
                    let output = line.split(separator: "\n").map { line -> SystemEvent<XcodeBuildOutput> in
                        SystemEvent.standardError(XcodeBuildOutput(raw: "\(String(line))\n"))
                    }
                    return Observable.from(output)
                case let .standardOutput(outputData):
                    guard let line = String(data: outputData, encoding: .utf8) else { return Observable.empty() }
                    let output = line.split(separator: "\n").map { line -> SystemEvent<XcodeBuildOutput> in
                        SystemEvent.standardOutput(XcodeBuildOutput(raw: "\(String(line))\n"))
                    }
                    return Observable.from(output)
                }
            }
    }

    fileprivate func run(command: [String], pipedToArguments: [String]) -> Observable<SystemEvent<XcodeBuildOutput>> {
        System.shared.observable(command, pipedToArguments: pipedToArguments)
            .flatMap { event -> Observable<SystemEvent<XcodeBuildOutput>> in
                switch event {
                case let .standardError(errorData):
                    guard let line = String(data: errorData, encoding: .utf8) else { return Observable.empty() }
                    let output = line.split(separator: "\n").map { line -> SystemEvent<XcodeBuildOutput> in
                        SystemEvent.standardError(XcodeBuildOutput(raw: "\(String(line))\n"))
                    }
                    return Observable.from(output)
                case let .standardOutput(outputData):
                    guard let line = String(data: outputData, encoding: .utf8) else { return Observable.empty() }
                    let output = line.split(separator: "\n").map { line -> SystemEvent<XcodeBuildOutput> in
                        SystemEvent.standardOutput(XcodeBuildOutput(raw: "\(String(line))\n"))
                    }
                    return Observable.from(output)
                }
            }
    }
}
