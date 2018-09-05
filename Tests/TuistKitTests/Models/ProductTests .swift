import Foundation
@testable import TuistKit
@testable import xcodeproj
import XCTest

final class ProductTests: XCTestCase {
    func test_xcodeValue() {
        XCTAssertEqual(Product.app.xcodeValue, PBXProductType.application)
        XCTAssertEqual(Product.staticLibrary.xcodeValue, PBXProductType.staticLibrary)
        XCTAssertEqual(Product.dynamicLibrary.xcodeValue, PBXProductType.dynamicLibrary)
        XCTAssertEqual(Product.framework.xcodeValue, PBXProductType.framework)
        XCTAssertEqual(Product.unitTests.xcodeValue, PBXProductType.unitTestBundle)
        XCTAssertEqual(Product.uiTests.xcodeValue, PBXProductType.uiTestBundle)
//        XCTAssertEqual(Product.appExtension.xcodeValue, PBXProductType.appExtension)
//        XCTAssertEqual(Product.watchApp.xcodeValue, PBXProductType.watchApp)
//        XCTAssertEqual(Product.watch2App.xcodeValue, PBXProductType.watch2App)
//        XCTAssertEqual(Product.watchExtension.xcodeValue, PBXProductType.watchExtension)
//        XCTAssertEqual(Product.watch2Extension.xcodeValue, PBXProductType.watch2Extension)
//        XCTAssertEqual(Product.tvExtension.xcodeValue, PBXProductType.tvExtension)
//        XCTAssertEqual(Product.messagesApplication.xcodeValue, PBXProductType.messagesApplication)
//        XCTAssertEqual(Product.messagesExtension.xcodeValue, PBXProductType.messagesExtension)
//        XCTAssertEqual(Product.stickerPack.xcodeValue, PBXProductType.stickerPack)
    }

    func test_description() {
        XCTAssertEqual(Product.app.description, "application")
        XCTAssertEqual(Product.staticLibrary.description, "static library")
        XCTAssertEqual(Product.dynamicLibrary.description, "dynamic library")
        XCTAssertEqual(Product.framework.description, "framework")
        XCTAssertEqual(Product.unitTests.description, "unit tests")
        XCTAssertEqual(Product.uiTests.description, "ui tests")
//        XCTAssertEqual(Product.appExtension.description, "app extension")
//        XCTAssertEqual(Product.watchExtension.description, "watch extension")
//        XCTAssertEqual(Product.watch2Extension.description, "watch 2 extension")
//        XCTAssertEqual(Product.watchApp.description, "watch application")
//        XCTAssertEqual(Product.watch2App.description, "watch 2 application")
//        XCTAssertEqual(Product.tvExtension.description, "tv extension")
//        XCTAssertEqual(Product.messagesApplication.description, "iMessage application")
//        XCTAssertEqual(Product.messagesExtension.description, "iMessage extension")
//        XCTAssertEqual(Product.stickerPack.description, "stickers pack")
    }

    func test_forPlatform_when_ios() {
        let got = Product.forPlatform(.iOS)
        let expected: [Product] = [
            .app,
            .staticLibrary,
            .dynamicLibrary,
            .framework,
//            .appExtension,
//            .stickerPack,
//            .messagesApplication,
//            .messagesExtension,
            .unitTests,
            .uiTests,
        ]
        XCTAssertEqual(got, Set(expected))
    }

    func test_forPlatform_when_macOS() {
        let got = Product.forPlatform(.macOS)
        let expected: [Product] = [
            .app,
            .staticLibrary,
            .dynamicLibrary,
            .framework,
            .unitTests,
            .uiTests,
        ]
        XCTAssertEqual(got, Set(expected))
    }

    func test_forPlatform_when_tvOS() {
        let got = Product.forPlatform(.tvOS)
        let expected: [Product] = [
            .app,
            .staticLibrary,
            .dynamicLibrary,
            .framework,
//            .tvExtension,
            .unitTests,
            .uiTests,
        ]
        XCTAssertEqual(got, Set(expected))
    }

//    func test_forPlatform_when_watchOS() {
//        let got = Product.forPlatform(.watchOS)
//        let expected: [Product] = [
//            .app,
//            .staticLibrary,
//            .dynamicLibrary,
//            .framework,
//            .watchApp,
//            .watch2App,
//            .watchExtension,
//            .watch2Extension,
//        ]
//        XCTAssertEqual(got, Set(expected))
//    }
}
