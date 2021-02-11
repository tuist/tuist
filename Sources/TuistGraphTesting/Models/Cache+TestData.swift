import Foundation
import TSCBasic
@testable import TuistGraph

public extension Cache {
    static func test(profiles: [Cache.Profile] = [Cache.Profile.test()]) -> Cache {
        Cache(profiles: profiles)
    }
}

public extension Cache.Profile {
    static func test(name: String = "Development", configuration: String = "Debug") -> Cache.Profile {
        Cache.Profile(name: name, configuration: configuration)
    }
}
