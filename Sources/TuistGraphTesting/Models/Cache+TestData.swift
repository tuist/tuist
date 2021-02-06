import Foundation
import TSCBasic
@testable import TuistGraph

public extension Cache {
    static func test(profiles: [Cache.Profile] = [Cache.Profile.test()]) -> Cache {
        Cache(profiles: profiles)
    }
}

public extension Cache.Profile {
    static func test() -> Cache.Profile {
        Cache.Profile(name: "development", configuration: "Debug")
    }
}
