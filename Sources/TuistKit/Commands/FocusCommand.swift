import ArgumentParser
import Foundation
import RxBlocking
import RxSwift
import TSCBasic
import TuistCache
import TuistCore
import TuistGenerator
import TuistLoader
import TuistSupport

enum FocusCommandError: FatalError {
    case noSources

    var description: String {
        switch self {
        case .noSources:
            return "A list of targets is required: tuist focus MyTarget."
        }
    }

    var type: ErrorType {
        switch self {
        case .noSources:
            return .abort
        }
    }
}

/// The focus command generates the Xcode workspace and launches it on Xcode.
struct FocusCommand: ParsableCommand, HasTrackableParameters {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "focus",
                             abstract: "Opens Xcode ready to focus on the project in the current directory")
    }

    static var analyticsDelegate: TrackableParametersDelegate?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory containing the project you plan to focus on.",
        completion: .directory
    )
    var path: String?

    @Argument(help: "A list of targets in which you'd like to focus. Those and their dependant targets will be generated as sources.")
    var sources: [String] = []

    @Flag(
        name: .shortAndLong,
        help: "Don't open the project after generating it."
    )
    var noOpen: Bool = false

    @Flag(
        name: [.customShort("x"), .long],
        help: "When passed it uses xcframeworks (simulator and device) from the cache instead of frameworks (only simulator)."
    )
    var xcframeworks: Bool = false

    @Flag(
        name: [.customLong("no-cache")],
        help: "Ignore cached targets, and use their sources instead."
    )
    var ignoreCache: Bool = false

    func run() throws {
        if sources.isEmpty {
            throw FocusCommandError.noSources
        }
        FocusCommand.analyticsDelegate?.willRun(withParameters: [
            "xcframeworks": String(xcframeworks),
            "no-cache": String(ignoreCache),
            "n_targets": String(sources.count),
        ])
        try FocusService().run(path: path,
                               sources: Set(sources),
                               noOpen: noOpen,
                               xcframeworks: xcframeworks,
                               ignoreCache: ignoreCache)
    }
}
