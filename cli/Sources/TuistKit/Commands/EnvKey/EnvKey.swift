import ArgumentParser
import Foundation
import TuistSupport

/// Environment variable keys for Tuist commands
public enum EnvKey: String, CaseIterable {
    // BUILD OPTIONS
    case buildOptionsPlatforms = "TUIST_BUILD_OPTIONS_PLATFORMS"
    
    // TEST OPTIONS  
    case testPlatforms = "TUIST_TEST_PLATFORMS"
    
    // Add other existing keys as needed
    case buildOptionsScheme = "TUIST_BUILD_OPTIONS_SCHEME"
    case buildOptionsGenerate = "TUIST_BUILD_OPTIONS_GENERATE"
    case buildOptionsClean = "TUIST_BUILD_OPTIONS_CLEAN"
    case buildOptionsPath = "TUIST_BUILD_OPTIONS_PATH"
    case buildOptionsDevice = "TUIST_BUILD_OPTIONS_DEVICE"
    case buildOptionsPlatform = "TUIST_BUILD_OPTIONS_PLATFORM"
    case buildOptionsOS = "TUIST_BUILD_OPTIONS_OS"
    case buildOptionsRosetta = "TUIST_BUILD_OPTIONS_ROSETTA"
    case buildOptionsConfiguration = "TUIST_BUILD_OPTIONS_CONFIGURATION"
    case buildOptionsOutputPath = "TUIST_BUILD_OPTIONS_BUILD_OUTPUT_PATH"
    case buildOptionsDerivedDataPath = "TUIST_BUILD_OPTIONS_DERIVED_DATA_PATH"
    case buildOptionsGenerateOnly = "TUIST_BUILD_OPTIONS_GENERATE_ONLY"
    case buildOptionsPassthroughXcodeBuildArguments = "TUIST_BUILD_OPTIONS_PASSTHROUGH_XCODE_BUILD_ARGUMENTS"
    
    case testScheme = "TUIST_TEST_SCHEME"
    case testClean = "TUIST_TEST_CLEAN"
    case testNoUpload = "TUIST_TEST_NO_UPLOAD"
    case testPath = "TUIST_TEST_PATH"
    case testDevice = "TUIST_TEST_DEVICE"
    case testPlatform = "TUIST_TEST_PLATFORM"
    case testOS = "TUIST_TEST_OS"
    case testRosetta = "TUIST_TEST_ROSETTA"
    case testConfiguration = "TUIST_TEST_CONFIGURATION"
    case testSkipUITests = "TUIST_TEST_SKIP_UI_TESTS"
    case testSkipUnitTests = "TUIST_TEST_SKIP_UNIT_TESTS"
}

extension Option where Value == String? {
    public init(
        name: NameSpecification = .long,
        parsing: SingleValueParsingStrategy = .next,
        help: ArgumentHelp? = nil,
        completion: CompletionKind? = nil,
        transform: @escaping (String) throws -> Value.Wrapped,
        envKey: EnvKey
    ) {
        self.init(
            name: name,
            parsing: parsing,
            help: help,
            completion: completion,
            transform: transform
        )
    }
}

extension Option where Value == String {
    public init(
        name: NameSpecification = .long,
        parsing: SingleValueParsingStrategy = .next,
        help: ArgumentHelp? = nil,
        completion: CompletionKind? = nil,
        transform: @escaping (String) throws -> Value,
        envKey: EnvKey
    ) {
        self.init(
            name: name,
            parsing: parsing,
            help: help,
            completion: completion,
            transform: transform
        )
    }
}

extension Flag where Value == Bool {
    public init(
        name: NameSpecification = .long,
        help: ArgumentHelp? = nil,
        envKey: EnvKey
    ) {
        self.init(
            name: name,
            help: help
        )
    }
}

extension Argument where Value == String? {
    public init(
        help: ArgumentHelp? = nil,
        completion: CompletionKind? = nil,
        transform: @escaping (String) throws -> Value.Wrapped,
        envKey: EnvKey
    ) {
        self.init(
            help: help,
            completion: completion,
            transform: transform
        )
    }
}

extension Argument where Value == [String] {
    public init(
        parsing: ArgumentArrayParsingStrategy = .remaining,
        help: ArgumentHelp? = nil,
        completion: CompletionKind? = nil,
        transform: @escaping (String) throws -> Value.Element,
        envKey: EnvKey
    ) {
        self.init(
            parsing: parsing,
            help: help,
            completion: completion,
            transform: transform
        )
    }
}