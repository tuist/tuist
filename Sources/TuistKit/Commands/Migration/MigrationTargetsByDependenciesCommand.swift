import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

struct MigrationTargetsByDependenciesCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "list-targets",
                             abstract: "It lists the targets of a project sorted by number of dependencies.")
    }

    @Option(
        name: [.customShort("p"), .long],
        help: "The path to the Xcode project",
        completion: .directory
    )
    var xcodeprojPath: String


    func run() throws {
        try MigrationTargetsByDependenciesService().run(xcodeprojPath: AbsolutePath(xcodeprojPath, relativeTo: FileHandler.shared.currentPath))
    }
}
