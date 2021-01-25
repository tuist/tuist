import Foundation
import TSCBasic
@testable import TuistGraph

public extension Cache {
    static func test(flavors: [Cache.Flavor] = [Cache.Flavor.test()]) -> Cache {
        Cache(flavors: flavors)
    }
}

public extension Cache.Flavor {
    static func test() -> Cache.Flavor {
        Cache.Flavor(name: "development", configuration: "Debug")
    }
}
