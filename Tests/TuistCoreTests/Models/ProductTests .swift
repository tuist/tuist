import Foundation
import XcodeProj
import XCTest

@testable import TuistCore

final class ProductTests: XCTestCase {
    func test_xcodeValue() {
        XCTAssertEqual(Product.app.xcodeValue, PBXProductType.application)
        XCTAssertEqual(Product.staticLibrary.xcodeValue, PBXProductType.staticLibrary)
        XCTAssertEqual(Product.dynamicLibrary.xcodeValue, PBXProductType.dynamicLibrary)
        XCTAssertEqual(Product.framework.xcodeValue, PBXProductType.framework)
        XCTAssertEqual(Product.unitTests.xcodeValue, PBXProductType.unitTestBundle)
        XCTAssertEqual(Product.uiTests.xcodeValue, PBXProductType.uiTestBundle)
        XCTAssertEqual(Product.appExtension.xcodeValue, PBXProductType.appExtension)
        XCTAssertEqual(Product.stickerPackExtension.xcodeValue, PBXProductType.stickerPack)
        XCTAssertEqual(Product.appClips.xcodeValue, PBXProductType.onDemandInstallCapableApplication)
    }

    func test_description() {
        XCTAssertEqual(Product.app.description, "application")
        XCTAssertEqual(Product.staticLibrary.description, "static library")
        XCTAssertEqual(Product.dynamicLibrary.description, "dynamic library")
        XCTAssertEqual(Product.framework.description, "framework")
        XCTAssertEqual(Product.unitTests.description, "unit tests")
        XCTAssertEqual(Product.uiTests.description, "ui tests")
        XCTAssertEqual(Product.appExtension.description, "app extension")
        XCTAssertEqual(Product.stickerPackExtension.description, "sticker pack extension")
        XCTAssertEqual(Product.appClips.description, "appClips")
    }

    func test_forPlatform_when_ios() {
        let got = Product.forPlatform(.iOS)
        let expected: [Product] = [
            .app,
            .staticLibrary,
            .dynamicLibrary,
            .framework,
            .appExtension,
            .stickerPackExtension,
            //            .messagesApplication,
            .messagesExtension,
            .unitTests,
            .uiTests,
            .appClips,
        ]
        XCTAssertEqual(Set(got), Set(expected))
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

    func test_runnable() {
        Product.allCases.forEach { product in
            if [.app, .appClips].contains(product) {
                XCTAssertTrue(product.runnable)
            } else {
                XCTAssertFalse(product.runnable)
            }
        }
    }

    func test_testsBundle() {
        Product.allCases.forEach { product in
            if product == .uiTests || product == .unitTests {
                XCTAssertTrue(product.testsBundle)
            } else {
                XCTAssertFalse(product.testsBundle)
            }
        }
    }
}
