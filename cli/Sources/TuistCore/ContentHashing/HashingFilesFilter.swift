import Path

struct HashingFilesFilter: Sendable {
    /// an array of filters, which should return if a path should be included in hashing calculations or not.
    private let filters: [@Sendable (AbsolutePath) -> Bool]

    init() {
        filters = [
            { $0.basename.uppercased() != ".DS_STORE" },
        ]
    }

    func callAsFunction(_ path: AbsolutePath) -> Bool {
        !filters.contains(where: { $0(path) == false })
    }
}
