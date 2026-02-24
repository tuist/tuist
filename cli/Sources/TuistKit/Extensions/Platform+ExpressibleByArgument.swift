import ArgumentParser
import XcodeGraph

extension XcodeGraph.Platform: @retroactive ArgumentParser.ExpressibleByArgument {
    public init?(argument: String) {
        self.init(commandLineValue: argument)
    }
}
