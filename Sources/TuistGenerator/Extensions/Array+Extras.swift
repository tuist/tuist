extension Array where Element == String {
    func uniqued() -> [String] {
        return Set(self).sorted { $0.compare($1, options: .caseInsensitive) == .orderedAscending }
    }
}
