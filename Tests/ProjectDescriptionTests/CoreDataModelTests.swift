import Foundation
@testable import ProjectDescription
import XCTest

final class CoreDataModelTests: XCTestCase {
    func test_toJSON() {
        let subject = CoreDataModel("path", currentVersion: "current")

        XCTAssertEqual(subject.toJSON().toString(), "{\"current_version\": \"current\", \"path\": \"path\"}")
    }
}
