import Foundation
import Testing
import TuistCore
import XcodeGraph
import XcodeProj
@testable import TuistGenerator

struct SettingsHelpersTests {
    private let subject: SettingsHelper
    init() {
        subject = SettingsHelper()
    }

    @Test
    func extend_whenNoSettings() {
        // Given
        var settings: [String: SettingValue] = [:]

        // When
        subject.extend(buildSettings: &settings, with: [:])

        // Then
        #expect(settings == [:])
    }

    @Test
    func extend_whenNoSettingsAndNewSettings() {
        // Given
        var settings: [String: SettingValue] = [:]

        // When
        subject.extend(buildSettings: &settings, with: ["A": "A_VALUE"])

        // Then
        #expect(settings == ["A": "A_VALUE"])
    }

    @Test
    func extend_whenExistingSettingsAndNewSettings() {
        // Given
        var settings: [String: SettingValue] = [:]
        settings["A"] = "A_VALUE"

        // When
        subject.extend(buildSettings: &settings, with: ["B": "B_VALUE"])

        // Then
        #expect(settings == ["A": "A_VALUE", "B": "B_VALUE"])
    }

    @Test
    func extend_whenExistingSettingsAndNewWithDifferentValues() {
        // Given
        var settings: [String: SettingValue] = [:]
        settings["A"] = "A_VALUE"
        settings["B"] = "B_VALUE"

        // When
        subject.extend(buildSettings: &settings, with: ["A": "A_VALUE_2", "C": "C_VALUE"])

        // Then
        #expect(settings == ["A": "A_VALUE_2", "B": "B_VALUE", "C": "C_VALUE"])
    }

    @Test
    func extend_whenExistingSettingsAndNewWithInheritedDeclaration() {
        // Given
        var settings: [String: SettingValue] = [:]
        settings["A"] = "A_VALUE"
        settings["B"] = "B_VALUE"

        // When
        subject.extend(buildSettings: &settings, with: ["A": "$(inherited) A_VALUE_2", "C": "C_VALUE"])

        // Then
        #expect(settings == [
            "A": ["$(inherited) A_VALUE_2", "A_VALUE"],
            "B": "B_VALUE",
            "C": "C_VALUE",
        ])
    }

    @Test
    func extend_whenArraySettings() {
        // Given
        var settings: [String: SettingValue] = [:]
        settings["A"] = "A_VALUE"
        settings["B"] = "B_VALUE"

        // When
        subject.extend(buildSettings: &settings, with: ["A": ["$(inherited)", "A_VALUE_2"], "C": "C_VALUE"])

        // Then
        #expect(settings == ["A": ["$(inherited)", "A_VALUE", "A_VALUE_2"], "B": "B_VALUE", "C": "C_VALUE"])
    }

    @Test
    func notExtend_whenExistingSettingsAndNewWithSameValues() {
        // Given
        var settings: [String: SettingValue] = [:]
        settings["A"] = "A_VALUE"
        settings["B"] = "B_VALUE"

        // When
        subject.extend(buildSettings: &settings, with: ["A": "A_VALUE"])

        // Then
        #expect(settings == ["A": "A_VALUE", "B": "B_VALUE"])
    }

    @Test
    func notExtend_whenExistingSettingsAndNewWithInheritedDeclarationAndSameValues() {
        // Given
        var settings: [String: SettingValue] = [:]
        settings["A"] = "$(inherited) A_VALUE"

        // When
        subject.extend(buildSettings: &settings, with: ["A": "$(inherited) A_VALUE"])

        // Then
        #expect(settings == ["A": "$(inherited) A_VALUE"])
    }

    @Test
    func extend_whenExistingSettingsArrayAndNewWithSomeStringValue() {
        // Given
        var settings: [String: SettingValue] = [:]
        settings["A"] = ["A_VALUE"]

        // When
        subject.extend(buildSettings: &settings, with: ["A": "A_VALUE_2 A_VALUE_3"])

        // Then
        #expect(settings == ["A": "A_VALUE_2 A_VALUE_3"])
    }

    @Test
    func extend_whenExistingSettingsArrayAndNewWithInheritedDeclarationAndSomeStringValue() {
        // Given
        var settings: [String: SettingValue] = [:]
        settings["A"] = ["A_VALUE"]

        // When
        subject.extend(buildSettings: &settings, with: ["A": "$(inherited) A_VALUE_2 A_VALUE_3"])

        // Then
        #expect(settings == ["A": ["$(inherited) A_VALUE_2 A_VALUE_3", "A_VALUE"]])
    }

    @Test
    func extend_whenExistingSettingsArrayAndNewWithSomeArrayValue() {
        // Given
        var settings: [String: SettingValue] = [:]
        settings["A"] = ["A_VALUE"]

        // When
        subject.extend(buildSettings: &settings, with: ["A": ["A_VALUE_2", "A_VALUE_3"]])

        // Then
        #expect(settings == ["A": ["A_VALUE_2", "A_VALUE_3"]])
    }

    @Test
    func extend_whenExistingSettingsArrayAndNewWithInheritedDeclarationAndSomeArrayValue() {
        // Given
        var settings: [String: SettingValue] = [:]
        settings["A"] = ["A_VALUE"]

        // When
        subject.extend(buildSettings: &settings, with: ["A": ["$(inherited)", "A_VALUE_2", "A_VALUE_3"]])

        // Then
        #expect(settings == ["A": ["$(inherited)", "A_VALUE", "A_VALUE_2", "A_VALUE_3"]])
    }

    @Test
    func extend_whenExistingSettingsArrayAndNewWithInheritedDeclarationAndArrayWithInheritedDeclaration() {
        // Given
        var settings: [String: SettingValue] = [:]
        settings["A"] = ["$(inherited)", "A_VALUE"]

        // When
        subject.extend(buildSettings: &settings, with: ["A": ["$(inherited)", "A_VALUE_2", "A_VALUE_3"]])

        // Then
        #expect(settings == ["A": ["$(inherited)", "A_VALUE", "A_VALUE_2", "A_VALUE_3"]])
    }

    @Test
    func extend_whenExistingSettingsArrayWithDuplicatesAndNewWithInheritedDeclaration() {
        // Given
        var settings: [String: SettingValue] = [:]
        settings["A"] = ["$(inherited)", "A_VALUE", "B_VALUE", "A_VALUE", "C_VALUE"]

        // When
        subject.extend(buildSettings: &settings, with: ["A": ["$(inherited)", "A_VALUE_1"]])

        // Then
        #expect(settings == ["A": [
            "$(inherited)",
            "A_VALUE",
            "B_VALUE",
            "A_VALUE",
            "C_VALUE",
            "A_VALUE_1",
        ]])
    }

    @Test
    func extend_whenExistingSettingsStringWithDuplicatesAndNewWithInheritedDeclaration() {
        // Given
        var settings: [String: SettingValue] = [:]
        settings["A"] = "$(inherited) A_VALUE B_VALUE A_VALUE C_VALUE"

        // When
        subject.extend(buildSettings: &settings, with: ["A": "$(inherited) A_VALUE_1"])

        // Then
        #expect(settings == ["A": [
            "$(inherited) A_VALUE_1",
            "A_VALUE B_VALUE A_VALUE C_VALUE",
        ]])
    }

    @Test
    func testSettingsProviderPlatform() {
        #expect(subject.settingsProviderPlatform(.iOS) == .iOS)
        #expect(subject.settingsProviderPlatform(.macOS) == .macOS)
        #expect(subject.settingsProviderPlatform(.tvOS) == .tvOS)
    }

    @Test
    func testSettingsProviderProduct() {
        #expect(subject.settingsProviderProduct(.test(product: .app)) == .application)
        #expect(subject.settingsProviderProduct(.test(product: .dynamicLibrary)) == .dynamicLibrary)
        #expect(subject.settingsProviderProduct(.test(product: .staticLibrary)) == .staticLibrary)
        #expect(subject.settingsProviderProduct(.test(product: .staticFramework)) == .framework)
        #expect(subject.settingsProviderProduct(.test(product: .framework)) == .framework)
        #expect(subject.settingsProviderProduct(.test(product: .unitTests)) == .unitTests)
        #expect(subject.settingsProviderProduct(.test(product: .uiTests)) == .uiTests)
        #expect(subject.settingsProviderProduct(.test(product: .appClip)) == .application)
        #expect(subject.settingsProviderProduct(.test(product: .appExtension)) == .appExtension)
        #expect(subject.settingsProviderProduct(.test(product: .messagesExtension)) == .appExtension)
        #expect(subject.settingsProviderProduct(.test(product: .bundle)) == nil)
    }

    @Test
    func testVariant() {
        #expect(subject.variant(BuildConfiguration(name: "Test", variant: .debug)) == .debug)
        #expect(subject.variant(BuildConfiguration(name: "Test", variant: .release)) == .release)
    }
}
