/// The kinds of files a buildable folder declares it will contain, so that generation doesn't depend on the files
/// present on disk.
public enum BuildableFolderContent: String, Sendable, Codable, Hashable {
    case sources
    case resources
}
