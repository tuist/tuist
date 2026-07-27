import Foundation

/// Parses the output of `absolute-unit` (shipped alongside `index-import`) into an ``IndexStoreUnit``.
///
/// `absolute-unit` prints a YAML-like description of an index unit: a top-level `OutputFile:` plus a
/// `Dependencies:` list whose entries each have a `DependencyKind` and, for record dependencies, a
/// `UnitOrRecordName`. We only need the output path (for target attribution) and the record names
/// (to copy alongside the unit).
public enum AbsoluteUnitOutputParser {
    /// Parses the output of `absolute-unit` invoked with several units at once. Each unit is printed as
    /// a `---` separated block whose `# <path>` header identifies it, so we split on those headers and
    /// parse each block, returning the units keyed by the header path.
    public static func parseAll(_ output: String) -> [String: IndexStoreUnit] {
        var units: [String: IndexStoreUnit] = [:]
        var currentPath: String?
        var currentLines: [Substring] = []

        func flush() {
            guard let currentPath else { return }
            units[currentPath] = parse(currentLines.joined(separator: "\n"))
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("# ") {
                flush()
                currentPath = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                currentLines = []
            } else if line == "---" {
                continue
            } else {
                currentLines.append(line)
            }
        }
        flush()
        return units
    }

    public static func parse(_ output: String) -> IndexStoreUnit {
        var outputFile = ""
        var recordNames: [String] = []
        var currentDependencyKind: String?

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)

            // `OutputFile:` only appears unindented at the top level; a dependency's own paths are
            // indented, so matching the raw line avoids picking up a dependency's `FilePath`.
            if line.hasPrefix("OutputFile:") {
                outputFile = value(of: line)
                continue
            }

            var trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") {
                trimmed = String(trimmed.dropFirst(2))
            }

            if trimmed.hasPrefix("DependencyKind:") {
                currentDependencyKind = value(of: trimmed)
            } else if trimmed.hasPrefix("UnitOrRecordName:") {
                let name = value(of: trimmed)
                if currentDependencyKind == "Record", !name.isEmpty {
                    recordNames.append(name)
                }
            }
        }

        return IndexStoreUnit(outputFile: outputFile, recordNames: recordNames)
    }

    private static func value(of line: String) -> String {
        guard let colonIndex = line.firstIndex(of: ":") else { return "" }
        return String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
    }
}
