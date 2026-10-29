import ArgumentParser

struct RunnerVolumeOptions: ParsableArguments {
    @Option(name: .long, help: "Account handle. Defaults to the account in the project's full handle.")
    var account: String?
    @Option(name: .shortAndLong, help: "Project directory.", completion: .directory)
    var path: String?
    @Flag(help: "Return response data and pagination as JSON. Unknown optional values are omitted.")
    var json = false
}
