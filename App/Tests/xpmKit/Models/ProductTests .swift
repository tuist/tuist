import Foundation
@testable import xcodeproj
import XCTest
@testable import xpmKit

final class ProductTests: XCTestCase {
    func test_xcodeValue() {
        XCTAssertEqual(Product.app.xcodeValue, PBXProductType.application)
        XCTAssertEqual(Product.staticLibrary.xcodeValue, PBXProductType.staticLibrary)
        XCTAssertEqual(Product.dynamicLibrary.xcodeValue, PBXProductType.dynamicLibrary)
        XCTAssertEqual(Product.framework.xcodeValue, PBXProductType.framework)
        XCTAssertEqual(Product.unitTests.xcodeValue, PBXProductType.unitTestBundle)
        XCTAssertEqual(Product.uiTests.xcodeValue, PBXProductType.uiTestBundle)
        XCTAssertEqual(Product.appExtension.xcodeValue, PBXProductType.appExtension)
        XCTAssertEqual(Product.watchApp.xcodeValue, PBXProductType.watchApp)
        XCTAssertEqual(Product.watch2App.xcodeValue, PBXProductType.watch2App)
        XCTAssertEqual(Product.watchExtension.xcodeValue, PBXProductType.watchExtension)
        XCTAssertEqual(Product.watch2Extension.xcodeValue, PBXProductType.watch2Extension)
        XCTAssertEqual(Product.tvExtension.xcodeValue, PBXProductType.tvExtension)
        XCTAssertEqual(Product.messagesApplication.xcodeValue, PBXProductType.messagesApplication)
        XCTAssertEqual(Product.messagesExtension.xcodeValue, PBXProductType.messagesExtension)
        XCTAssertEqual(Product.stickerPack.xcodeValue, PBXProductType.stickerPack)
    }
}
