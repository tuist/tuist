/// The kinds of files a buildable folder declares it will contain.
public enum BuildableFolderContent: String, Sendable, Codable, Hashable {
    case sources
    case resources
}
