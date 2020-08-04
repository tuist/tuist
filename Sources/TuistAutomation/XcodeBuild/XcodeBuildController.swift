import Foundation
import RxSwift
import TSCBasic
import TuistCore
import TuistSupport
import XcbeautifyLib

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

    /// Instance to format xcodebuild output.
    private let parser: Parsing

    public convenience init() {
        self.init(parser: Parser())
    }

    init(parser: Parsing) {
        self.parser = parser
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
        command.append(contentsOf: arguments.flatMap { $0.arguments })

        return run(command: command)
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
        command.append(contentsOf: arguments.flatMap { $0.arguments })

        return run(command: command)
    }

    public func createXCFramework(frameworks: [AbsolutePath], output: AbsolutePath) -> Observable<SystemEvent<XcodeBuildOutput>> {
        var command = ["/usr/bin/xcrun", "xcodebuild", "-create-xcframework"]
        command.append(contentsOf: frameworks.flatMap { ["-framework", $0.pathString] })
        command.append(contentsOf: ["-output", output.pathString])
        command.append("-allow-internal-distribution")
        return run(command: command)
    }

    public func showBuildSettings(_ target: XcodeBuildTarget,
                                  scheme: String,
                                  configuration: String) -> Single<[String: XcodeBuildSettings]>
    {
        var command = ["/usr/bin/xcrun", "xcodebuild", "archive", "-showBuildSettings", "-skipUnavailableActions"]

        // Configuration
        command.append(contentsOf: ["-configuration", configuration])

        // Scheme
        command.append(contentsOf: ["-scheme", scheme])

        // Target
        command.append(contentsOf: target.xcodebuildArguments)

        return System.shared.observable(command)
            .mapToString()
            .collectAndMergeOutput()
            // xcodebuild has a bug where xcodebuild -showBuildSettings
            // can sometimes hang indefinitely on projects that don't
            // share any schemes, so automatically bail out if it looks
            // like that's happening.
            .timeout(DispatchTimeInterval.seconds(20), scheduler: ConcurrentDispatchQueueScheduler(queue: .global()))
            .retry(5)
            .flatMap { string -> Observable<XcodeBuildSettings> in
                Observable.create { (observer) -> Disposable in
                    var currentSettings: [String: String] = [:]
                    var currentTarget: String?

                    let flushTarget = { () -> Void in
                        if let currentTarget = currentTarget {
                            let buildSettings = XcodeBuildSettings(currentSettings, target: currentTarget, configuration: configuration)
                            observer.onNext(buildSettings)
                        }

                        currentTarget = nil
                        currentSettings = [:]
                    }

                    string.enumerateLines { line, _ in
                        if let result = XcodeBuildController.targetSettingsRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
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
            .reduce([String: XcodeBuildSettings](), accumulator: { (acc, buildSettings) -> [String: XcodeBuildSettings] in
                var acc = acc
                acc[buildSettings.target] = buildSettings
                return acc
            })
            .asSingle()
    }

    fileprivate func run(command: [String]) -> Observable<SystemEvent<XcodeBuildOutput>> {
        let colored = Environment.shared.shouldOutputBeColoured
        return System.shared.observable(command, verbose: false)
            .flatMap { event -> Observable<SystemEvent<XcodeBuildOutput>> in
                switch event {
                case let .standardError(errorData):
                    guard let line = String(data: errorData, encoding: .utf8) else { return Observable.empty() }
                    return Observable.create { observer in
                        let lines = line.split(separator: "\n")
                        lines.map { line in
                            let formatedOutput = self.parser.parse(line: String(line), colored: colored)
                            return SystemEvent.standardError(XcodeBuildOutput(raw: "\(String(line))\n", formatted: formatedOutput.map { "\($0)\n" }))
                        }
                        .forEach(observer.onNext)
                        observer.onCompleted()
                        return Disposables.create()
                    }
                case let .standardOutput(outputData):
                    guard let line = String(data: outputData, encoding: .utf8) else { return Observable.empty() }

                    return Observable.create { observer in
                        let lines = line.split(separator: "\n")
                        lines.map { line in
                            let formatedOutput = self.parser.parse(line: String(line), colored: colored)
                            return SystemEvent.standardOutput(XcodeBuildOutput(raw: "\(String(line))\n", formatted: formatedOutput.map { "\($0)\n" }))
                        }
                        .forEach(observer.onNext)
                        observer.onCompleted()
                        return Disposables.create()
                    }
                }
            }
    }
}
