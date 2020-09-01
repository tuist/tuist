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
struct FocusCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "focus",
                             abstract: "Opens Xcode ready to focus on the project in the current directory")
    }

    @Flag(help: "Generate a project replacing dependencies with pre-compiled assets.")
    var cache: Bool = false

    @Option(
        name: NameSpecification([.customShort("i"), .customLong("include-sources", withSingleDash: false)]),
        parsing: .singleValue,
        help: "When used with --cache, it generates the given target (with the sources) even if it exists in the cache."
    )
    var includeSources: [String] = []

    @Option(
        name: .shortAndLong,
        help: "The path to the directory containing the project you plan to focus on.",
        completion: .directory
    )
    var path: String?

    @Flag(
        name: .shortAndLong,
        help: "Don't open the project after generating it."
    )
    var noOpen: Bool = false

    func run() throws {
        try FocusService().run(cache: cache,
                               path: path,
                               includeSources: Set(includeSources),
                               noOpen: noOpen)
    }
}
