import Foundation
@testable import ProjectDescription
import XCTest

final class CoreDataModelTests: XCTestCase {
    func test_toJSON() {
        let subject = CoreDataModel("path", currentVersion: "current")

        assertCodableEqualToJson(subject, "{\"current_version\": \"current\", \"path\": \"path\"}")
    }
}
