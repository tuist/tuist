import TuistCore

extension CacheProfileType {
    static func from(commandLineValue value: String) -> Self {
        switch value {
        case "only-external":
            return .onlyExternal
        case "all-possible":
            return .allPossible
        case "none":
            return .none
        default:
            return .custom(value)
        }
    }
}
