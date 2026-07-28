import Path

public enum TargetHashingInput: Equatable, Hashable, Codable, Sendable {
    case path(AbsolutePath, isDeclaredAbsolute: Bool)
    case string(String)
    case environmentVariable(String)
    case script(String)
}
