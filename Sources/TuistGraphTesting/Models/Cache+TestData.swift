import Foundation
import TSCBasic
import struct TSCUtility.Version
@testable import TuistGraph

extension Cache {
    public static func test(profiles: [Cache.Profile] = [Cache.Profile.test()]) -> Cache {
        Cache(profiles: profiles, path: nil)
    }
}

extension Cache.Profile {
    public static func test(
        name: String = "Development",
        configuration: String = "Debug",
        device: String? = nil,
        os: Version? = nil
    ) -> Cache.Profile {
        Cache.Profile(name: name, configuration: configuration, device: device, os: os)
    }
}
