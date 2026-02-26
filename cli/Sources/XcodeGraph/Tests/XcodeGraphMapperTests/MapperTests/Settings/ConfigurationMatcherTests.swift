import Testing
import XcodeGraph
@testable import XcodeGraphMapper

@Suite
struct ConfigurationMatcherTests {
    let configurationMatcher: ConfigurationMatching

    init(configurationMatcher: ConfigurationMatching = ConfigurationMatcher()) {
        self.configurationMatcher = configurationMatcher
    }

    @Test("Detects 'Debug' variants from configuration names")
    func variantDetectionForDebug() {
        // Given
        // The configurationMatcher is already set up by the initializer.

        // When
        let variantDebug = configurationMatcher.variant(for: "Debug")
        let variantDevelopment = configurationMatcher.variant(for: "development")
        let variantDev = configurationMatcher.variant(for: "dev")

        // Then
        #expect(variantDebug == .debug)
        #expect(variantDevelopment == .debug)
        #expect(variantDev == .debug)
    }

    @Test("Detects 'Release' variants from configuration names")
    func variantDetectionForRelease() {
        // Given
        // The configurationMatcher is already set up by the initializer.

        // When
        let variantRelease = configurationMatcher.variant(for: "Release")
        let variantProd = configurationMatcher.variant(for: "prod")
        let variantProduction = configurationMatcher.variant(for: "production")

        // Then
        #expect(variantRelease == .release)
        #expect(variantProd == .release)
        #expect(variantProduction == .release)
    }

    @Test("Falls back to 'Debug' variant for unrecognized configuration names")
    func variantFallbackToDebug() {
        // Given
        // The configurationMatcher is already set up by the initializer.

        // When
        let variantStaging = configurationMatcher.variant(for: "Staging")
        let variantCustom = configurationMatcher.variant(for: "CustomConfig")

        // Then
        #expect(variantStaging == .debug)
        #expect(variantCustom == .debug)
    }

    @Test("Validates configuration names based on allowed patterns")
    func testValidateConfigurationName() {
        // Given
        // The configurationMatcher is already set up by the initializer.

        // When
        let validDebug = configurationMatcher.validateConfigurationName("Debug")
        let validRelease = configurationMatcher.validateConfigurationName("Release")
        let invalidEmpty = configurationMatcher.validateConfigurationName("")
        let invalidSpaceInName = configurationMatcher.validateConfigurationName("Debug Config")
        let invalidSpaceOnly = configurationMatcher.validateConfigurationName(" ")

        // Then
        #expect(validDebug == true)
        #expect(validRelease == true)
        #expect(invalidEmpty == false)
        #expect(invalidSpaceInName == false)
        #expect(invalidSpaceOnly == false)
    }
}
