extension Array where Element == String {
    func uniqued() -> [String] {
        Set(self).sorted { $0.compare($1, options: .caseInsensitive) == .orderedAscending }
    }

    func sortAndTrim(element: String) -> [String] {
        guard contains(where: { $0.starts(with: element) }) else { return self }
        // Move items that contain `element` to the top of the array
        return sorted { first, _ in
            first.contains(element)
        }.enumerated().compactMap { index, item in
            // Remove duplicate `element`
            if index > 0,
               item == element
            {
                return nil
            } else if index > 0, item.contains(element) {
                // "$(inherited) flag" -> "flag"
                return item
                    .replacingOccurrences(of: element, with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                return item
            }
        }
    }
}
