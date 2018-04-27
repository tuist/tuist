import Foundation
@testable import xcbuddykit
import XCTest

final class ProductTests: XCTestCase {
    func test_xcodeValue() {
        XCTAssertEqual(Product.app.xcodeValue, "com.apple.product-type.application")
        XCTAssertEqual(Product.staticLibrary.xcodeValue, "com.apple.product-type.library.static")
        XCTAssertEqual(Product.dynamicLibrary.xcodeValue, "com.apple.product-type.library.dynamic")
        XCTAssertEqual(Product.framework.xcodeValue, "com.apple.product-type.framework")
        XCTAssertEqual(Product.unitTests.xcodeValue, "com.apple.product-type.bundle.unit-test")
        XCTAssertEqual(Product.uiTests.xcodeValue, "com.apple.product-type.bundle.ui-testing")
        XCTAssertEqual(Product.appExtension.xcodeValue, "com.apple.product-type.app-extension")
        XCTAssertEqual(Product.watchApp.xcodeValue, "com.apple.product-type.application.watchapp")
        XCTAssertEqual(Product.watch2App.xcodeValue, "com.apple.product-type.application.watchapp2")
        XCTAssertEqual(Product.watchExtension.xcodeValue, "com.apple.product-type.watchkit-extension")
        XCTAssertEqual(Product.watch2Extension.xcodeValue, "com.apple.product-type.watchkit2-extension")
        XCTAssertEqual(Product.tvExtension.xcodeValue, "com.apple.product-type.tv-app-extension")
        XCTAssertEqual(Product.messagesApplication.xcodeValue, "com.apple.product-type.application.messages")
        XCTAssertEqual(Product.messagesExtension.xcodeValue, "com.apple.product-type.app-extension.messages")
        XCTAssertEqual(Product.stickerPack.xcodeValue, "com.apple.product-type.app-extension.messages-sticker-pack")
    }
}
