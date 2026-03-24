import Foundation
import Testing
import TuistTesting
@testable import ProjectDescription

struct CloudTests {
    @Test func config_toJSON() throws {
        let cloud = Cloud(url: "https://cloud.tuist.io", projectId: "123", options: [])
        #expect(try isCodableRoundTripable(cloud))
    }
}
