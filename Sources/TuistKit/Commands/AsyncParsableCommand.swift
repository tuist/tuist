import ArgumentParser

public protocol AsyncParsableCommand: ParsableCommand {
    mutating func runAsync() async throws
}
