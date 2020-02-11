import Basic
import Foundation
import SPMUtility

func main() throws {
    let parser = ArgumentParser(commandName: "FixtureGenerator",
                                usage: "FixtureGenerator <options>",
                                overview: "Generates large fixtures for the purposes of stress testing Tuist")

    let fileSystem = localFileSystem
    let generateCommand = GenerateCommand(fileSystem: fileSystem,
                                          parser: parser)

    let arguments = ProcessInfo.processInfo.arguments
    let results = try parser.parse(Array(arguments.dropFirst()))
    try generateCommand.run(with: results)
}

do {
    try main()
} catch {
    print("Error: \(error.localizedDescription)")
}
