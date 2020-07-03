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

    func run() throws {
        try FocusService().run(cache: true)
    }
}
