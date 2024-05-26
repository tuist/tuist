import ArgumentParser
import TuistGraph
import TSCUtility
import Foundation
import TuistSupport
import TuistCore

extension TuistGraph.Platform: EnumerableFlag, ExpressibleByArgument {}

extension Version: ExpressibleByArgument {
    
    public var defaultValueDescription: String {
       "14.5"
    }
    
    public static var allValueStrings: [String] {
        [
            "15.0, 16.0"
        ]
    }
}
