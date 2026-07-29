import ArgumentParser

struct LoggingOptions: ParsableArguments {
    @Flag(
        name: .long,
        help: "Display verbose logs."
    )
    var verbose: Bool = false
}
