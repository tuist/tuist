/// Represents the different options to configure a target for mergeable libraries
public enum MergedBinaryType: Equatable, Codable {
    /// Target is never going to merge available dependencies
    case disabled
    /// Target is going to merge direct target dependencies (just the ones declared as part of it's project)
    case automatic
    /// Target is going to merge direct and specified dependencies that are not part of the project.
    case manual(mergeableDependencies: Set<String>)
}
