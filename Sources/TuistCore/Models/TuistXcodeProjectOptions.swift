public struct TuistXcodeProjectOptions: Codable, Equatable, Sendable, Hashable {
    public init() {}
}

#if DEBUG
    extension TuistXcodeProjectOptions {
        static func test() -> Self {
            return TuistXcodeProjectOptions()
        }
    }
#endif
