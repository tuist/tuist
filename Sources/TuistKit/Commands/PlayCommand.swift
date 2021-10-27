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

enum PlayCommandError: FatalError {
    case noSources

    var description: String {
        switch self {
        case .noSources:
            return "A list of targets is required: tuist play MyTarget."
        }
    }

    var type: ErrorType {
        switch self {
        case .noSources:
            return .abort
        }
    }
}

struct PlayCommand: ParsableCommand, HasTrackableParameters {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "play",
            abstract: "Generates a temporary workspace with a playground to play with a target"
        )
    }

    static var analyticsDelegate: TrackableParametersDelegate?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory containing the project you plan to play with.",
        completion: .directory
    )
    var path: String?

    @Argument(help: "A list of targets that you'd like to play with. Those and their dependant targets will be generated as sources.")
    var sources: [String] = []

    @Flag(
        name: [.customShort("x"), .long],
        help: "When passed it uses xcframeworks (simulator and device) from the cache instead of frameworks (only simulator)."
    )
    var xcframeworks: Bool = false

    @Option(
        name: [.customShort("P"), .long],
        help: "The name of the cache profile to be used when playing with the target."
    )
    var profile: String?

    @Flag(
        name: [.customLong("no-cache")],
        help: "Ignore cached targets, and use their sources instead."
    )
    var ignoreCache: Bool = false

    func run() throws {
        print("it works")
        if sources.isEmpty {
            throw PlayCommandError.noSources
        }
        PlayCommand.analyticsDelegate?.willRun(withParameters: [:
//            "xcframeworks": String(xcframeworks),
//            "no-cache": String(ignoreCache),
//            "n_targets": String(sources.count),
        ])
        try PlayService().run(
            path: path,
            sources: Set(sources),
            xcframeworks: xcframeworks,
            profile: profile,
            ignoreCache: ignoreCache
        )
    }
}
