extension [String] {
    func uniqued() -> [String] {
        Set(self).sorted { $0.compare($1, options: .caseInsensitive) == .orderedAscending }
    }
}
