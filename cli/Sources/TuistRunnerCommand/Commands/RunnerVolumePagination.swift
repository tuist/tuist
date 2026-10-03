import ArgumentParser

struct RunnerVolumePagination: ParsableArguments {
    @Option(name: .long, help: "Page number, starting at 1.")
    var page = 1
    @Option(name: .long, help: "Results per page (1–100).")
    var pageSize = 20

    func validate() throws {
        guard (1 ... 100_000).contains(page), (1 ... 100).contains(pageSize) else {
            throw ValidationError("Page must be 1–100000 and page size must be 1–100.")
        }
    }
}
