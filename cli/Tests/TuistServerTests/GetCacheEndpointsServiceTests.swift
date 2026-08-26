import Foundation
import Testing

@testable import TuistServer

struct GetCacheEndpointsServiceTests {
    @Test func reads_max_age_out_of_a_cache_control_value() {
        #expect(GetCacheEndpointsService.maxAge(from: "private, max-age=3600") == 3600)
        #expect(GetCacheEndpointsService.maxAge(from: "max-age=30") == 30)
        #expect(GetCacheEndpointsService.maxAge(from: "private, Max-Age = 30") == 30)
    }

    @Test func has_no_max_age_when_the_server_does_not_give_one() {
        #expect(GetCacheEndpointsService.maxAge(from: nil) == nil)
        #expect(GetCacheEndpointsService.maxAge(from: "no-store") == nil)
        #expect(GetCacheEndpointsService.maxAge(from: "private, max-age=soon") == nil)
    }
}
