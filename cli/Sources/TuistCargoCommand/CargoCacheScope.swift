struct CargoCacheScope {
    let accountHandle: String
    let instanceName: String

    init?(fullHandle: String) {
        let components = fullHandle.lowercased().split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2, components.allSatisfy({ !$0.isEmpty }) else { return nil }
        accountHandle = String(components[0])
        instanceName = String(components[1])
    }
}
