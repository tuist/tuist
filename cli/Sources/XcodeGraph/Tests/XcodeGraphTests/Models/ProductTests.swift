import Foundation
import Testing
@testable import XcodeGraph

struct ProductTests {
    @Test func test_codable_app() throws {
        // Given
        let subject = Product.app

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(Product.self, from: data)
        #expect(subject == decoded)
    }

    @Test func test_codable_staticFramework() throws {
        // Given
        let subject = Product.staticFramework

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(Product.self, from: data)
        #expect(subject == decoded)
    }

    @Test func test_codable_watch2AppContainer() throws {
        // Given
        let subject = Product.watch2AppContainer

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(Product.self, from: data)
        #expect(subject == decoded)
    }

    @Test func test_description() {
        #expect(Product.app.description == "application")
        #expect(Product.staticLibrary.description == "static library")
        #expect(Product.dynamicLibrary.description == "dynamic library")
        #expect(Product.framework.description == "dynamic framework")
        #expect(Product.unitTests.description == "unit tests")
        #expect(Product.uiTests.description == "ui tests")
        #expect(Product.appExtension.description == "app extension")
        #expect(Product.stickerPackExtension.description == "sticker pack extension")
        #expect(Product.appClip.description == "appClip")
        #expect(Product.watch2AppContainer.description == "watch 2 app container")
    }

    @Test func test_forPlatform_when_ios() {
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
        #expect(Set(got) == Set(expected))
    }

    @Test func test_forPlatform_when_macOS() {
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
            .systemExtension,
            .macro,
        ]
        #expect(got == Set(expected))
    }

    @Test func test_forPlatform_when_tvOS() {
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
        #expect(got == Set(expected))
    }

    @Test func test_runnable() {
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
            .extensionKitExtension,
            .macro,
        ]
        for product in Product.allCases {
            if runnables.contains(product) {
                #expect(product.runnable)
            } else {
                #expect(!product.runnable)
            }
        }
    }

    @Test func test_testsBundle() {
        for product in Product.allCases {
            if product == .uiTests || product == .unitTests {
                #expect(product.testsBundle)
            } else {
                #expect(!product.testsBundle)
            }
        }
    }

    @Test func test_can_host_tests() {
        // App
        var subject = Product.app
        #expect(subject.canHostTests())

        // App Clip
        subject = Product.appClip
        #expect(subject.canHostTests())

        // App Extension
        subject = Product.appExtension
        #expect(!subject.canHostTests())

        // Watch App
        subject = Product.appClip
        #expect(subject.canHostTests())

        // Watch2Extension
        subject = Product.watch2Extension
        #expect(!subject.canHostTests())

        // UITests
        subject = Product.uiTests
        #expect(!subject.canHostTests())

        // UnitTests
        subject = Product.unitTests
        #expect(!subject.canHostTests())

        // Framework
        subject = Product.framework
        #expect(!subject.canHostTests())

        // Static Framework
        subject = Product.staticFramework
        #expect(!subject.canHostTests())

        // Static Library
        subject = Product.staticLibrary
        #expect(!subject.canHostTests())

        // Dynamic Library
        subject = Product.dynamicLibrary
        #expect(!subject.canHostTests())

        // Bundle
        subject = Product.bundle
        #expect(!subject.canHostTests())

        // Command Line Tool
        subject = Product.commandLineTool
        #expect(!subject.canHostTests())

        // Messages Extension
        subject = Product.messagesExtension
        #expect(!subject.canHostTests())

        // Sticker Pack Extension
        subject = Product.stickerPackExtension
        #expect(!subject.canHostTests())

        // TV Top Shelf Extension
        subject = Product.tvTopShelfExtension
        #expect(!subject.canHostTests())

        // XPC
        subject = Product.xpc
        #expect(!subject.canHostTests())

        // System Extension
        subject = Product.systemExtension
        #expect(!subject.canHostTests())

        // Watch 2 App Container
        subject = Product.watch2AppContainer
        #expect(!subject.canHostTests())
    }
}
