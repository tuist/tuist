import ArgumentParser
import Foundation

// MARK: - DocCommand

struct DocCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "doc",
                             abstract: "Generates documentation for a specifc target.")
    }
    
    // MARK: - Attributes
    
    @OptionGroup()
    var options: DocCommand.Options
        
    // MARK: - Run

    func run() throws {
        try DocService().run(paths: options.inputs)
    }
}

// MARK: - Options

extension DocCommand {
    struct Options: ParsableArguments {
        @Argument(help: "One or more paths to Swift files")
        var inputs: [String] = []
        
        @Option(name: [.long, .customShort("n")],
                help: "The name of the module")
        var moduleName: String
        
        @Option(name: .shortAndLong,
                help: "The path for generated output")
        var output: String = "./build/documentation"
    }
}
