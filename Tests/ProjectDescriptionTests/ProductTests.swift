import Foundation
@testable import ProjectDescription
import XCTest

final class ProductTests: XCTestCase {
    func test_toJSON_returns_the_right_value() {
        XCTAssertEqual(Product.app.toJSON().toString(), "\"app\"")
        XCTAssertEqual(Product.module.toJSON().toString(), "\"module\"")
        XCTAssertEqual(Product.unitTests.toJSON().toString(), "\"unitTests\"")
        XCTAssertEqual(Product.uiTests.toJSON().toString(), "\"uiTests\"")
        XCTAssertEqual(Product.appExtension.toJSON().toString(), "\"appExtension\"")
        XCTAssertEqual(Product.watchApp.toJSON().toString(), "\"watchApp\"")
        XCTAssertEqual(Product.watch2App.toJSON().toString(), "\"watch2App\"")
        XCTAssertEqual(Product.watchExtension.toJSON().toString(), "\"watchExtension\"")
        XCTAssertEqual(Product.watch2Extension.toJSON().toString(), "\"watch2Extension\"")
        XCTAssertEqual(Product.tvExtension.toJSON().toString(), "\"tvExtension\"")
        XCTAssertEqual(Product.messagesApplication.toJSON().toString(), "\"messagesApplication\"")
        XCTAssertEqual(Product.messagesExtension.toJSON().toString(), "\"messagesExtension\"")
        XCTAssertEqual(Product.stickerPack.toJSON().toString(), "\"stickerPack\"")
    }
}
