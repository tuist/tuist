import ArgumentParser
import TuistGraph
import TSCUtility
import Foundation
import TuistSupport
import TuistCore

extension TuistGraph.Platform: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(commandLineValue: argument)
    }
}

extension Version: ExpressibleByArgument { }
