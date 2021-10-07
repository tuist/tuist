import Foundation
import TSCBasic
import struct TSCUtility.Version
@testable import TuistGraph

public extension Cache {
    static func test(profiles: [Cache.Profile] = [Cache.Profile.test()]) -> Cache {
        Cache(profiles: profiles, path: nil)
    }
}

public extension Cache.Profile {
    static func test(
        name: String = "Development",
        configuration: String = "Debug",
        device: String? = nil,
        os: Version? = nil
    ) -> Cache.Profile {
        Cache.Profile(name: name, configuration: configuration, device: device, os: os)
    }
}
