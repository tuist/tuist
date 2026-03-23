import Foundation
import Testing
import TuistTesting

@testable import ProjectDescription

struct CoreDataModelTests {
    @Test func test_toJSON() throws {
        let subject: CoreDataModel = .coreDataModel("path", currentVersion: "current")
        #expect(try isCodableRoundTripable(subject))
    }
}
