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

/// The focus command generates the Xcode workspace and launches it on Xcode.
struct FocusCommand: ParsableCommand, HasTrackableParameters {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "focus",
            abstract: "Opens Xcode ready to focus on the project in the current directory"
        )
    }

    static var analyticsDelegate: TrackableParametersDelegate?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory containing the project you plan to focus on.",
        completion: .directory
    )
    var path: String?

    @Argument(help: """
    A list of targets in which you'd like to focus. \
    Those and their dependant targets will be generated as sources. \
    If no target is specified, the project defined targets will be focused.
    """)
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

    @Option(
        name: [.customShort("P"), .long],
        help: "The name of the cache profile to be used when focusing on the target."
    )
    var profile: String?

    @Flag(
        name: [.customLong("no-cache")],
        help: "Ignore cached targets, and use their sources instead."
    )
    var ignoreCache: Bool = false

    func run() throws {
        FocusCommand.analyticsDelegate?.willRun(withParameters: [
            "xcframeworks": String(xcframeworks),
            "no-cache": String(ignoreCache),
            "n_targets": String(sources.count),
        ])
        try FocusService().run(
            path: path,
            sources: Set(sources),
            noOpen: noOpen,
            xcframeworks: xcframeworks,
            profile: profile,
            ignoreCache: ignoreCache
        )
    }
}
