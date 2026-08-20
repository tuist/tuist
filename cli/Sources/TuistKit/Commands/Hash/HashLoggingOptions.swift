import ArgumentParser

struct HashLoggingOptions: ParsableArguments {
    @Flag(
        name: .long,
        help: "Display verbose logs, including the individual sub-hashes that make up each target's hash."
    )
    var verbose: Bool = false
}
