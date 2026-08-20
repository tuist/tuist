/// The configuration the binary cache hashes were computed against, along with how it was resolved.
public struct CacheHashingConfiguration: Equatable, Sendable {
    public enum Resolution: Equatable, Sendable {
        case flag
        case manifest
        case debugVariantFallback

        public var description: String {
            switch self {
            case .flag:
                return "the --configuration flag"
            case .manifest:
                return "generationOptions.defaultConfiguration in the manifest"
            case .debugVariantFallback:
                return "a fallback to the project's first debug-variant configuration"
            }
        }
    }

    public let name: String
    public let resolution: Resolution

    public init(name: String, resolution: Resolution) {
        self.name = name
        self.resolution = resolution
    }
}
