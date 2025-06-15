public struct TuistSwiftPackageOptions: Codable, Equatable, Sendable, Hashable {
    public init() {}
}

#if DEBUG
    extension TuistSwiftPackageOptions {
        static func test() -> Self {
            return TuistSwiftPackageOptions()
        }
    }
#endif
