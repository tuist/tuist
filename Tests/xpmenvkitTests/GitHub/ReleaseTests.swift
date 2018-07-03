import Foundation
import Utility
import XCTest
@testable import xpmenvkit

final class ReleaseTests: XCTestCase {
    func test_asset_init_returns_nil_when_browser_download_url_is_missing() {
        let json: [String: Any] = [:]
        let got = Release.Asset(json: json)
        XCTAssertNil(got)
    }

    func test_asset_init() {
        let json: [String: Any] = ["browser_download_url": "https://download.com"]
        let got = Release.Asset(json: json)
        XCTAssertEqual(got?.downloadURL, URL(string: "https://download.com"))
    }

    func test_init_returns_nil_when_tag_name_is_missing() {
        var json = self.json()
        json.removeValue(forKey: "tag_name")
        let got = Release(json: json)
        XCTAssertNil(got)
    }

    func test_init_returns_nil_when_id_is_missing() {
        var json = self.json()
        json.removeValue(forKey: "id")
        let got = Release(json: json)
        XCTAssertNil(got)
    }

    func test_init_returns_nil_when_body_is_missing() {
        var json = self.json()
        json.removeValue(forKey: "body")
        let got = Release(json: json)
        XCTAssertNil(got)
    }

    func test_init_returns_nil_when_name_is_missing() {
        var json = self.json()
        json.removeValue(forKey: "name")
        let got = Release(json: json)
        XCTAssertNil(got)
    }

    func test_init_returns_nil_when_assets_is_missing() {
        let json = self.json()
        let got = Release(json: json)
        XCTAssertEqual(got?.version, Version(string: "3.2.1"))
        XCTAssertEqual(got?.id, 333)
        XCTAssertEqual(got?.body, "body")
        XCTAssertEqual(got?.name, "name")
        XCTAssertEqual(got?.assets.first?.downloadURL, URL(string: "https://download.com"))
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
