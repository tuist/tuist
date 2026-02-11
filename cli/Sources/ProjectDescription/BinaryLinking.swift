/// Describes how a binary artifact is linked.
public enum BinaryLinking: String, Codable, Hashable, Sendable {
    case `static`, dynamic
}
