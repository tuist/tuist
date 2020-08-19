import ArgumentParser
import Foundation
import TSCBasic

struct RunCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "run",
                             abstract: "Builds and runs a project")
    }
    
    @Argument(
        help: "The scheme to be guild. By default it builds all the buildable schemes of the project in the current directory"
    )
    var schemeName: String
    
    @Option(
        name: [.long, .customShort("C")],
        help: "The configuration to be used when building the scheme."
    )
    var configutation: String?
    
    func run() throws {
        try RunService().run(schemeName: schemeName)
    }
}
