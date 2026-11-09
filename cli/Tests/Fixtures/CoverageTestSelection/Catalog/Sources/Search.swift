public enum ProductSearch {
    public static func matches(name: String, query: String) -> Bool {
        query.isEmpty || name.localizedCaseInsensitiveContains(query)
    }
}
