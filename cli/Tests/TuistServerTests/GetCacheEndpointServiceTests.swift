import Foundation
import Testing

@testable import TuistServer

struct GetCacheEndpointServiceTests {
    @Test func reads_max_age_out_of_a_cache_control_value() {
        #expect(GetCacheEndpointService.maxAge(from: "private, max-age=3600") == 3600)
        #expect(GetCacheEndpointService.maxAge(from: "max-age=30") == 30)
        #expect(GetCacheEndpointService.maxAge(from: "private, Max-Age = 30") == 30)
    }

    @Test func has_no_max_age_when_the_server_does_not_give_one() {
        #expect(GetCacheEndpointService.maxAge(from: "max-age=-1") == nil)
        #expect(GetCacheEndpointService.maxAge(from: "max-age=inf") == nil)
        #expect(GetCacheEndpointService.maxAge(from: nil) == nil)
        #expect(GetCacheEndpointService.maxAge(from: "no-store") == nil)
        #expect(GetCacheEndpointService.maxAge(from: "private, max-age=soon") == nil)
    }
}
