import Foundation
import Testing
import TuistTesting

@testable import ProjectDescription

struct CoreDataModelTests {
    @Test func toJSON() throws {
        let subject: CoreDataModel = .coreDataModel("path", currentVersion: "current")
        #expect(try isCodableRoundTripable(subject))
    }
}
