import Configuration

#if Tuist
    public struct TuistTrait {
        public init() {}
    }
public func isTesting() async throws -> Bool {
    let jsonProvider = try await FileProvider<JSONSnapshot>(
        filePath: "/test.json"
    )
    let config = ConfigReader(provider: jsonProvider)
    return config.bool(forKey: "TESTING", default: true)
}

#endif
