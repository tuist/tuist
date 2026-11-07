/// The files a process's function records name: what each Swift Testing test case's task entered,
/// and the floor, what no test's task did (see `TestCoverageEvidenceService.reduce`).
struct TaskFiles {
    struct Test: Hashable {
        var module: String
        var suite: String
        var name: String
    }

    /// The files of the functions each test case's task entered, by test.
    var tests: [Test: Set<String>] = [:]
    /// The files of the functions no test's task entered.
    var floor: Set<String> = []
    /// Every file function tracking saw run in the process.
    var seen: Set<String> = []

    /// Nil when the process has no function records or any of them names a function that can't be
    /// told: an image without symbols, or an offset before every symbol. A test whose files are
    /// partly unknown, or a floor that is, would leave out what it depends on.
    init?(
        of output: CoverageObserverOutput,
        symbols: [String: ImageSymbols],
        filesBySymbol: [String: [String: Set<String>]]
    ) {
        guard !output.functionRecords.isEmpty else { return nil }
        for record in output.functionRecords {
            var recordFiles: Set<String> = []
            for (index, offsets) in record.offsets {
                guard let image = output.functionImages[index], let table = symbols[image] else { return nil }
                let files = filesBySymbol[image] ?? [:]
                for offset in offsets {
                    guard let function = table.function(atOffset: UInt64(offset)) else { return nil }
                    recordFiles.formUnion(files[function] ?? [])
                }
            }
            seen.formUnion(recordFiles)
            if record.floor {
                floor.formUnion(recordFiles)
            } else {
                tests[Test(module: record.module, suite: record.suite, name: record.name), default: []].formUnion(recordFiles)
            }
        }
    }

    /// Each test's files with those every test of the process may depend on: the floor, and what the
    /// counters saw run among the Swift Testing tests (`untracked`) that function tracking didn't,
    /// such as code built without it.
    func files(beside untracked: Set<String>) -> [Test: Set<String>] {
        let shared = floor.union(untracked.subtracting(seen))
        return tests.mapValues { $0.union(shared) }
    }

    /// `filesByFunction` keyed by the symbol a function record resolves to: the profile names a
    /// function with internal linkage `<file>:<symbol>`, and the symbol table only `<symbol>`.
    static func filesBySymbol(_ filesByFunction: [String: [String: Set<String>]]) -> [String: [String: Set<String>]] {
        filesByFunction.mapValues { table in
            var bySymbol = table
            for (function, files) in table {
                guard let separator = function.lastIndex(of: ":") else { continue }
                let symbol = String(function[function.index(after: separator)...])
                guard symbol.hasPrefix("$s") || symbol.hasPrefix("_$s") || symbol.hasPrefix("$S") else { continue }
                bySymbol[symbol, default: []].formUnion(files)
            }
            return bySymbol
        }
    }
}
