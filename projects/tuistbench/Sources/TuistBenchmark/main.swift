import Foundation
import TSCBasic
import TSCUtility

func main() throws {
    let parser = ArgumentParser(
        commandName: "tuistbench",
        usage: "<options>",
        overview: "A utility to benchmark running tuist against a set of fixtures."
    )

    let fileHandler = FileHandler()
    let generateCommand = BenchmarkCommand(
        fileHandler: fileHandler,
        parser: parser
    )

    let arguments = ProcessInfo.processInfo.arguments
    let results = try parser.parse(Array(arguments.dropFirst()))
    try generateCommand.run(with: results)
}

do {
    try main()
} catch {
    print("Error: \(error.localizedDescription)")
    exit(1)
}
