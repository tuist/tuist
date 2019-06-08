import Foundation
import XcodeProj
import XCTest
@testable import TuistGenerator

final class SettingsHelpersTests: XCTestCase {
    private var subject = SettingsHelper()
    private var settings: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        subject = SettingsHelper()
        settings = [:]
    }

    func testExtend_whenNoSettings() {
        // When
        subject.extend(buildSettings: &settings, with: [:])

        // Then
        XCTAssertEqualDictionaries(settings, [:])
    }

    func testExtend_whenNoSettingsAndNewSettings() {
        // When
        subject.extend(buildSettings: &settings, with: ["A": "A_VALUE"])

        // Then
        XCTAssertEqualDictionaries(settings, ["A": "A_VALUE"])
    }

    func testExtend_whenExistingSettingsAndNewSettings() {
        // Given
        settings["A"] = "A_VALUE"

        // When
        subject.extend(buildSettings: &settings, with: ["B": "B_VALUE"])

        // Then
        XCTAssertEqualDictionaries(settings, ["A": "A_VALUE", "B": "B_VALUE"])
    }

    func testExtend_whenExistingSettingsAndNewWithDifferentValues() {
        // Given
        settings["A"] = "A_VALUE"
        settings["B"] = "B_VALUE"

        // When
        subject.extend(buildSettings: &settings, with: ["A": "A_VALUE_2", "C": "C_VALUE"])

        // Then
        XCTAssertEqualDictionaries(settings, ["A": "A_VALUE_2", "B": "B_VALUE", "C": "C_VALUE"])
    }

    func testExtend_whenExistingSettingsAndNewWithInheritedDeclaration() {
        // Given
        settings["A"] = "A_VALUE"
        settings["B"] = "B_VALUE"

        // When
        subject.extend(buildSettings: &settings, with: ["A": "$(inherited) A_VALUE_2", "C": "C_VALUE"])

        // Then
        XCTAssertEqualDictionaries(settings, ["A": "A_VALUE $(inherited) A_VALUE_2", "B": "B_VALUE", "C": "C_VALUE"])
    }

    func testNotExtend_whenExistingSettingsAndNewWithSameValues() {
        // Given
        settings["A"] = "A_VALUE"
        settings["B"] = "B_VALUE"

        // When
        subject.extend(buildSettings: &settings, with: ["A": "A_VALUE"])

        // Then
        XCTAssertEqualDictionaries(settings, ["A": "A_VALUE", "B": "B_VALUE"])
    }

    func testNotExtend_whenExistingSettingsAndNewWithInheritedDeclarationAndSameValues() {
        // Given
        settings["A"] = "$(inherited) A_VALUE"

        // When
        subject.extend(buildSettings: &settings, with: ["A": "$(inherited) A_VALUE"])

        // Then
        XCTAssertEqualDictionaries(settings, ["A": "$(inherited) A_VALUE"])
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
        XCTAssertNil(subject.settingsProviderProduct(.test(product: .bundle)))
        XCTAssertNil(subject.settingsProviderProduct(.test(product: .unitTests)))
        XCTAssertNil(subject.settingsProviderProduct(.test(product: .uiTests)))
    }

    func testVariant() {
        XCTAssertEqual(subject.variant(BuildConfiguration(name: "Test", variant: .debug)), .debug)
        XCTAssertEqual(subject.variant(BuildConfiguration(name: "Test", variant: .release)), .release)
    }
}
