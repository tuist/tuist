import ArgumentParser
import TuistCore

extension TargetQuery: @retroactive ExpressibleByArgument {
    public init?(argument: String) {
        self.init(stringLiteral: argument)
    }
}

extension CacheProfileType: @retroactive ExpressibleByArgument {
    public init?(argument: String) {
        self.init(stringLiteral: argument)
    }
}
