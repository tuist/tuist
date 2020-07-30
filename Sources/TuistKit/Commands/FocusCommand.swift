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
    var cache: Bool

    @Option(
        name: .shortAndLong,
        help: "The path to the directory containing the project you plan to focus on.",
        completion: .directory
    )
    var path: String?

    func run() throws {
        try FocusService().run(cache: cache, path: path)
    }
}
