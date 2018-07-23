import Foundation
@testable import TuistEnvKit
import Utility
import XCTest

final class ReleaseDecodeErrorTests: XCTestCase {
    func test_errorDescription() {
        let expected = "Invalid release version format: 3.2. It should have a valid semver format: x.y.z."
        XCTAssertEqual(ReleaseDecodeError.invalidVersionFormat("3.2").description, expected)
    }

    func test_equatable_when_invalid_version() {
        XCTAssertEqual(ReleaseDecodeError.invalidVersionFormat("3.2"), ReleaseDecodeError.invalidVersionFormat("3.2"))
        XCTAssertNotEqual(ReleaseDecodeError.invalidVersionFormat("3.2"), ReleaseDecodeError.invalidVersionFormat("3.2.1"))
    }
}

final class ReleaseTests: XCTestCase {
    func test_init_throws_when_invalid_version() throws {
        var json = self.json()
        json["tag_name"] = "3.2"
        let decoder = JSONDecoder()
        let data = try JSONSerialization.data(withJSONObject: json, options: [])
        XCTAssertThrowsError(try decoder.decode(Release.self, from: data)) {
            XCTAssertEqual($0 as? ReleaseDecodeError, ReleaseDecodeError.invalidVersionFormat("3.2"))
        }
    }

    func test_release_coding_keys() {
        XCTAssertEqual(Release.CodingKeys.version.rawValue, "tag_name")
    }

    func test_asset_coding_keys() {
        XCTAssertEqual(Release.Asset.CodingKeys.downloadURL.rawValue, "browser_download_url")
    }

    // MARK: - Fileprivate

    fileprivate func json() -> [String: Any] {
        return [
            "tag_name": "3.2.1",
            "id": 333,
            "body": "body",
            "name": "name",
            "assets": [[
                "browser_download_url": "https://download.com",
            ]],
        ]
    }
}
