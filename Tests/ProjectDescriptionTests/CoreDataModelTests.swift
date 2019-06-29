import Foundation
import TuistCoreTesting
import XCTest

@testable import ProjectDescription

final class CoreDataModelTests: XCTestCase {
    func test_toJSON() {
        let subject = CoreDataModel("path", currentVersion: "current")

        XCTAssertCodableEqualToJson(subject, "{\"current_version\": \"current\", \"path\": \"path\"}")
    }
}
