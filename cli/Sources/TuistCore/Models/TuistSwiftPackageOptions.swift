public struct TuistSwiftPackageOptions: Codable, Equatable, Sendable, Hashable {
    public let disableSandbox: Bool

    public init(disableSandbox: Bool = true) {
        self.disableSandbox = disableSandbox
    }
}

#if DEBUG
    extension TuistSwiftPackageOptions {
        static func test(disableSandbox: Bool = true) -> Self {
            return TuistSwiftPackageOptions(disableSandbox: disableSandbox)
        }
    }
#endif
