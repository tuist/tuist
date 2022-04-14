import Foundation
import TuistCore
import TuistCoreTesting
import TuistGraph
import XcodeProj
import XCTest
@testable import TuistGenerator

final class SettingsHelpersTests: XCTestCase {
    private var subject: SettingsHelper!
    private var settings: [String: SettingValue]!

    override func setUp() {
        super.setUp()
        subject = SettingsHelper()
        settings = [:]
    }

    override func tearDown() {
        settings = nil
        subject = nil
        super.tearDown()
    }

    func testExtend_whenNoSettings() {
        // When
        subject.extend(buildSettings: &settings, with: [:])

        // Then
        XCTAssertEqual(settings, [:])
    }

    func testExtend_whenNoSettingsAndNewSettings() {
        // When
        subject.extend(buildSettings: &settings, with: ["A": "A_VALUE"])

        // Then
        XCTAssertEqual(settings, ["A": "A_VALUE"])
    }

    func testExtend_whenExistingSettingsAndNewSettings() {
        // Given
        settings["A"] = "A_VALUE"

        // When
        subject.extend(buildSettings: &settings, with: ["B": "B_VALUE"])

        // Then
        XCTAssertEqual(settings, ["A": "A_VALUE", "B": "B_VALUE"])
    }

    func testExtend_whenExistingSettingsAndNewWithDifferentValues() {
        // Given
        settings["A"] = "A_VALUE"
        settings["B"] = "B_VALUE"

        // When
        subject.extend(buildSettings: &settings, with: ["A": "A_VALUE_2", "C": "C_VALUE"])

        // Then
        XCTAssertEqual(settings, ["A": "A_VALUE_2", "B": "B_VALUE", "C": "C_VALUE"])
    }

    func testExtend_whenExistingSettingsAndNewWithInheritedDeclaration() {
        // Given
        settings["A"] = "A_VALUE"
        settings["B"] = "B_VALUE"

        // When
        subject.extend(buildSettings: &settings, with: ["A": "$(inherited) A_VALUE_2", "C": "C_VALUE"])

        // Then
        XCTAssertEqual(settings, [
            "A": ["$(inherited) A_VALUE_2", "A_VALUE"],
            "B": "B_VALUE",
            "C": "C_VALUE",
        ])
    }

    func testExtend_whenArraySettings() {
        // Given
        settings["A"] = "A_VALUE"
        settings["B"] = "B_VALUE"

        // When
        subject.extend(buildSettings: &settings, with: ["A": ["$(inherited)", "A_VALUE_2"], "C": "C_VALUE"])

        // Then
        XCTAssertEqual(settings, ["A": ["$(inherited)", "A_VALUE", "A_VALUE_2"], "B": "B_VALUE", "C": "C_VALUE"])
    }

    func testNotExtend_whenExistingSettingsAndNewWithSameValues() {
        // Given
        settings["A"] = "A_VALUE"
        settings["B"] = "B_VALUE"

        // When
        subject.extend(buildSettings: &settings, with: ["A": "A_VALUE"])

        // Then
        XCTAssertEqual(settings, ["A": "A_VALUE", "B": "B_VALUE"])
    }

    func testNotExtend_whenExistingSettingsAndNewWithInheritedDeclarationAndSameValues() {
        // Given
        settings["A"] = "$(inherited) A_VALUE"

        // When
        subject.extend(buildSettings: &settings, with: ["A": "$(inherited) A_VALUE"])

        // Then
        XCTAssertEqual(settings, ["A": "$(inherited) A_VALUE"])
    }

    func testExtend_whenExistingSettingsArrayAndNewWithSomeStringValue() {
        // Given
        settings["A"] = ["A_VALUE"]

        // When
        subject.extend(buildSettings: &settings, with: ["A": "A_VALUE_2 A_VALUE_3"])

        // Then
        XCTAssertEqual(settings, ["A": "A_VALUE_2 A_VALUE_3"])
    }

    func testExtend_whenExistingSettingsArrayAndNewWithInheritedDeclarationAndSomeStringValue() {
        // Given
        settings["A"] = ["A_VALUE"]

        // When
        subject.extend(buildSettings: &settings, with: ["A": "$(inherited) A_VALUE_2 A_VALUE_3"])

        // Then
        XCTAssertEqual(settings, ["A": ["$(inherited) A_VALUE_2 A_VALUE_3", "A_VALUE"]])
    }

    func testExtend_whenExistingSettingsArrayAndNewWithSomeArrayValue() {
        // Given
        settings["A"] = ["A_VALUE"]

        // When
        subject.extend(buildSettings: &settings, with: ["A": ["A_VALUE_2", "A_VALUE_3"]])

        // Then
        XCTAssertEqual(settings, ["A": ["A_VALUE_2", "A_VALUE_3"]])
    }

    func testExtend_whenExistingSettingsArrayAndNewWithInheritedDeclarationAndSomeArrayValue() {
        // Given
        settings["A"] = ["A_VALUE"]

        // When
        subject.extend(buildSettings: &settings, with: ["A": ["$(inherited)", "A_VALUE_2", "A_VALUE_3"]])

        // Then
        XCTAssertEqual(settings, ["A": ["$(inherited)", "A_VALUE", "A_VALUE_2", "A_VALUE_3"]])
    }

    func testExtend_whenExistingSettingsArrayAndNewWithInheritedDeclarationAndArrayWithInheritedDeclaration() {
        // Given
        settings["A"] = ["$(inherited)", "A_VALUE"]

        // When
        subject.extend(buildSettings: &settings, with: ["A": ["$(inherited)", "A_VALUE_2", "A_VALUE_3"]])

        // Then
        XCTAssertEqual(settings, ["A": ["$(inherited)", "A_VALUE", "A_VALUE_2", "A_VALUE_3"]])
    }

    func testExtend_whenExistingSettingsArrayWithDuplicatesAndNewWithInheritedDeclaration() {
        // Given
        settings["A"] = ["$(inherited)", "A_VALUE", "B_VALUE", "A_VALUE", "C_VALUE"]

        // When
        subject.extend(buildSettings: &settings, with: ["A": ["$(inherited)", "A_VALUE_1"]])

        // Then
        XCTAssertEqual(settings, ["A": [
            "$(inherited)",
            "A_VALUE",
            "B_VALUE",
            "A_VALUE",
            "C_VALUE",
            "A_VALUE_1",
        ]])
    }

    func testExtend_whenExistingSettingsStringWithDuplicatesAndNewWithInheritedDeclaration() {
        // Given
        settings["A"] = "$(inherited) A_VALUE B_VALUE A_VALUE C_VALUE"

        // When
        subject.extend(buildSettings: &settings, with: ["A": "$(inherited) A_VALUE_1"])

        // Then
        XCTAssertEqual(settings, ["A": [
            "$(inherited) A_VALUE_1",
            "A_VALUE B_VALUE A_VALUE C_VALUE",
        ]])
    }

    func testSettingsProviderPlatform() {
        XCTAssertEqual(subject.settingsProviderPlatform(.test(platform: .iOS)), .iOS)
        XCTAssertEqual(subject.settingsProviderPlatform(.test(platform: .macOS)), .macOS)
        XCTAssertEqual(subject.settingsProviderPlatform(.test(platform: .tvOS)), .tvOS)
    }

    func testSettingsProviderProduct() {
        XCTAssertEqual(subject.settingsProviderProduct(.test(product: .app)), .application)
        XCTAssertEqual(subject.settingsProviderProduct(.test(product: .dynamicLibrary)), .dynamicLibrary)
        XCTAssertEqual(subject.settingsProviderProduct(.test(product: .staticLibrary)), .staticLibrary)
        XCTAssertEqual(subject.settingsProviderProduct(.test(product: .staticFramework)), .framework)
        XCTAssertEqual(subject.settingsProviderProduct(.test(product: .framework)), .framework)
        XCTAssertEqual(subject.settingsProviderProduct(.test(product: .unitTests)), .unitTests)
        XCTAssertEqual(subject.settingsProviderProduct(.test(product: .uiTests)), .uiTests)
        XCTAssertEqual(subject.settingsProviderProduct(.test(product: .appClip)), .application)
        XCTAssertEqual(subject.settingsProviderProduct(.test(product: .appExtension)), .appExtension)
        XCTAssertEqual(subject.settingsProviderProduct(.test(product: .messagesExtension)), .appExtension)
        XCTAssertNil(subject.settingsProviderProduct(.test(product: .bundle)))
    }

    func testVariant() {
        XCTAssertEqual(subject.variant(BuildConfiguration(name: "Test", variant: .debug)), .debug)
        XCTAssertEqual(subject.variant(BuildConfiguration(name: "Test", variant: .release)), .release)
    }
}
