public enum ArtifactType: CustomStringConvertible {
    case framework
    case xcframework

    public var description: String {
        switch self {
        case .framework:
            return "framework"
        case .xcframework:
            return "xcframework"
        }
    }
}
