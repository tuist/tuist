import ArgumentParser
import TuistCore

extension TargetQuery: @retroactive ExpressibleByArgument {
    public init?(argument: String) {
        self.init(stringLiteral: argument)
    }
}

extension CacheProfileType: @retroactive ExpressibleByArgument {
    public init?(argument: String) {
        switch BaseCacheProfile(rawValue: argument) {
        case .onlyExternal:
            self = .onlyExternal
        case .allPossible:
            self = .allPossible
        case .none?:
            self = .none
        case nil:
            self = .custom(argument)
        }
    }
}
