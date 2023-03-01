import Foundation
import XcodeProj
import XCTest
@testable import TuistGraph

final class ProductTests: XCTestCase {
    func test_codable_app() {
        // Given
        let subject = Product.app

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_staticFramework() {
        // Given
        let subject = Product.staticFramework

        // Then
        XCTAssertCodable(subject)
    }

    func test_xcodeValue() {
        XCTAssertEqual(Product.app.xcodeValue, PBXProductType.application)
        XCTAssertEqual(Product.staticLibrary.xcodeValue, PBXProductType.staticLibrary)
        XCTAssertEqual(Product.dynamicLibrary.xcodeValue, PBXProductType.dynamicLibrary)
        XCTAssertEqual(Product.framework.xcodeValue, PBXProductType.framework)
        XCTAssertEqual(Product.unitTests.xcodeValue, PBXProductType.unitTestBundle)
        XCTAssertEqual(Product.uiTests.xcodeValue, PBXProductType.uiTestBundle)
        XCTAssertEqual(Product.appExtension.xcodeValue, PBXProductType.appExtension)
        XCTAssertEqual(Product.stickerPackExtension.xcodeValue, PBXProductType.stickerPack)
        XCTAssertEqual(Product.appClip.xcodeValue, PBXProductType.onDemandInstallCapableApplication)
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
        XCTAssertEqual(Product.appClip.description, "appClip")
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
            .appClip,
        ]
        XCTAssertEqual(Set(got), Set(expected))
    }

    func test_forPlatform_when_macOS() {
        let got = Product.forPlatform(.macOS)
        let expected: [Product] = [
            .app,
            .commandLineTool,
            .staticLibrary,
            .dynamicLibrary,
            .framework,
            .unitTests,
            .uiTests,
            .xpc,
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
            .tvTopShelfExtension,
            .unitTests,
            .uiTests,
        ]
        XCTAssertEqual(got, Set(expected))
    }

    func test_runnable() {
        let runnables: [Product] = [
            .app,
            .appClip,
            .commandLineTool,
            .watch2App,
            .appExtension,
            .messagesExtension,
            .stickerPackExtension,
            .tvTopShelfExtension,
            .watch2Extension,
        ]
        Product.allCases.forEach { product in
            if runnables.contains(product) {
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

    func test_can_host_tests() {
        // App
        var subject = Product.app
        XCTAssert(subject.canHostTests())

        // App Clip
        subject = Product.appClip
        XCTAssert(subject.canHostTests())

        // App Extension
        subject = Product.appExtension
        XCTAssertFalse(subject.canHostTests())

        // Watch App
        subject = Product.appClip
        XCTAssert(subject.canHostTests())

        // Watch2Extension
        subject = Product.watch2Extension
        XCTAssertFalse(subject.canHostTests())

        // UITests
        subject = Product.uiTests
        XCTAssertFalse(subject.canHostTests())

        // UnitTests
        subject = Product.unitTests
        XCTAssertFalse(subject.canHostTests())

        // Framework
        subject = Product.framework
        XCTAssertFalse(subject.canHostTests())

        // Static Framework
        subject = Product.staticFramework
        XCTAssertFalse(subject.canHostTests())

        // Static Library
        subject = Product.staticLibrary
        XCTAssertFalse(subject.canHostTests())

        // Dynamic Library
        subject = Product.dynamicLibrary
        XCTAssertFalse(subject.canHostTests())

        // Bundle
        subject = Product.bundle
        XCTAssertFalse(subject.canHostTests())

        // Command Line Tool
        subject = Product.commandLineTool
        XCTAssertFalse(subject.canHostTests())

        // Messages Extension
        subject = Product.messagesExtension
        XCTAssertFalse(subject.canHostTests())

        // Sticker Pack Extension
        subject = Product.stickerPackExtension
        XCTAssertFalse(subject.canHostTests())

        // TV Top Shelf Extension
        subject = Product.tvTopShelfExtension
        XCTAssertFalse(subject.canHostTests())

        // XPC
        subject = Product.xpc
        XCTAssertFalse(subject.canHostTests())
    }
}
