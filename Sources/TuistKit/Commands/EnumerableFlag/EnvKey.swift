import Foundation
import ArgumentParser
import TuistSupport

public enum EnvKey: String, CaseIterable {
    // BUILD OPTIONS
    case buildOptionsSchemes = "TUIST_BUILD_OPTIONS_SCHEMES"
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
    
    // CLEAN
    case cleanCleanCategories = "TUIST_CLEAN_CLEAN_CATEGORIES"
    case cleanPath = "TUIST_CLEAN_PATH"
    
    // DUMP
    case dumpPath = "TUIST_DUMP_PATH"
    case dumpManifest = "TUIST_DUMP_MANIFEST"
    
    // EDIT
    case editPath = "TUIST_EDIT_PATH"
    case editPermanent = "TUIST_EDIT_PERMANENT"
    case editOnlyCurrentDirectory = "TUIST_EDIT_ONLY_CURRENT_DIRECTORY"
    
    // INSTALL
    case installPath = "TUIST_INSTALL_PATH"
    case installUpdate = "TUIST_INSTALL_UPDATE"
    
    // GENERATE
    case generatePath = "TUIST_GENERATE_PATH"
    case generateOpen = "TUIST_GENERATE_OPEN"
    
    // GRAPH
    case graphSkipTestTargets = "TUIST_GRAPH_SKIP_TEST_TARGETS"
    case graphSkipExternalDependencies = "TUIST_GRAPH_SKIP_EXTERNAL_DEPENDENCIES"
    case graphPlatform = "TUIST_GRAPH_PLATFORM"
    case graphFormat = "TUIST_GRAPH_FORMAT"
    case graphOpen = "TUIST_GRAPH_OPEN"
    case graphLayoutAlgorithm = "TUIST_GRAPH_LAYOUT_ALGORITHM"
    case graphTargets = "TUIST_GRAPH_TARGETS"
    case graphPath = "TUIST_GRAPH_PATH"
    case graphOutputPath = "TUIST_GRAPH_OUTPUT_PATH"
    
    // INIT
    case initPlatform = "TUIST_INIT_PLATFORM"
    case initName = "TUIST_INIT_NAME"
    case initTemplate = "TUIST_INIT_TEMPLATE"
    case initPath = "TUIST_INIT_PATH"
    
    // MIGRATION
    case migrationSettingsToXcconfigXcodeprojPath = "TUIST_MIGRATION_SETTINGS_TO_XCCONFIG_XCODEPROJ_PATH"
    case migrationSettingsToXcconfigXcconfigPath = "TUIST_MIGRATION_SETTINGS_TO_XCCONFIG_XCCONFIG_PATH"
    case migrationSettingsToXcconfigTarget = "TUIST_MIGRATION_SETTINGS_TO_XCCONFIG_TARGET"
    case migrationCheckEmptySettingsXcodeprojPath = "TUIST_MIGRATION_CHECK_EMPTY_SETTINGS_XCODEPROJ_PATH"
    case migrationCheckEmptySettingsTarget = "TUIST_MIGRATION_CHECK_EMPTY_SETTINGS_TARGET"
    case migrationListTargetsXcodeprojPath = "TUIST_MIGRATION_LIST_TARGETS_XCODEPROJ_PATH"
    
    // PLUGIN
    case pluginArchivePath = "TUIST_PLUGIN_ARCHIVE_PATH"
    case pluginBuildBuildTests = "TUIST_PLUGIN_BUILD_BUILD_TESTS"
    case pluginBuildShowBinPath = "TUIST_PLUGIN_BUILD_SHOW_BIN_PATH"
    case pluginBuildTargets = "TUIST_PLUGIN_BUILD_TARGETS"
    case pluginBuildProducts = "TUIST_PLUGIN_BUILD_PRODUCTS"
    case pluginRunBuildTests = "TUIST_PLUGIN_RUN_BUILD_TESTS"
    case pluginRunSkipBuild = "TUIST_PLUGIN_RUN_SKIP_BUILD"
    case pluginRunTask = "TUIST_PLUGIN_RUN_TASK"
    case pluginRunArguments = "TUIST_PLUGIN_RUN_ARGUMENTS"
    case pluginTestBuildTests = "TUIST_PLUGIN_TEST_BUILD_TESTS"
    case pluginTestTestProducts = "TUIST_PLUGIN_TEST_TEST_PRODUCTS"


    // PLUGIN OPTIONS
    case pluginOptionsConfiguration = "TUIST_PLUGIN_OPTIONS_CONFIGURATION"
    case pluginOptionsPath = "TUIST_PLUGIN_OPTIONS_PATH"
    
    // RUN
    case runBuildTests = "TUIST_RUN_BUILD_TESTS"
    case runSkipBuild = "TUIST_RUN_SKIP_BUILD"
    case runTask = "TUIST_RUN_TASK"
    case runArguments = "TUIST_RUN_ARGUMENTS"
    case runGenerate = "TUIST_RUN_GENERATE"
    case runClean = "TUIST_RUN_CLEAN"
    case runPath = "TUIST_RUN_PATH"
    case runConfiguration = "TUIST_RUN_CONFIGURATION"
    case runDevice = "TUIST_RUN_DEVICE"
    case runOS = "TUIST_RUN_OS"
    case runRosetta = "TUIST_RUN_ROSETTA"
    case runScheme = "TUIST_RUN_SCHEME"
    
    // SCAFFOLD
    case scaffoldTemplate = "TUIST_SCAFFOLD_TEMPLATE"
    case scaffoldJson = "TUIST_SCAFFOLD_JSON"
    case scaffoldPath = "TUIST_SCAFFOLD_PATH"
    case scaffoldListJson = "TUIST_SCAFFOLD_LIST_JSON"
    case scaffoldListPath = "TUIST_SCAFFOLD_LIST_PATH"
    
    // TEST
    case testScheme = "TUIST_TEST_SCHEME"
    case testClean = "TUIST_TEST_CLEAN"
    case testPath = "TUIST_TEST_PATH"
    case testDevice = "TUIST_TEST_DEVICE"
    case testPlatform = "TUIST_TEST_PLATFORM"
    case testOS = "TUIST_TEST_OS"
    case testRosetta = "TUIST_TEST_ROSETTA"
    case testConfiguration = "TUIST_TEST_CONFIGURATION"
    case testSkipUITests = "TUIST_TEST_SKIP_UITESTS"
    case testResultBundlePath = "TUIST_TEST_RESULT_BUNDLE_PATH"
    case testDerivedDataPath = "TUIST_TEST_DERIVED_DATA_PATH"
    case testRetryCount = "TUIST_TEST_RETRY_COUNT"
    case testTestPlan = "TUIST_TEST_TEST_PLAN"
    case testTestTargets = "TUIST_TEST_TEST_TARGETS"
    case testSkipTestTargets = "TUIST_TEST_SKIP_TEST_TARGETS"
    case testConfigurations = "TUIST_TEST_CONFIGURATIONS"
    case testSkipConfigurations = "TUIST_TEST_SKIP_CONFIGURATIONS"
    case testGenerateOnly = "TUIST_TEST_GENERATE_ONLY"
}

extension EnvKey {
    var envValueString: String? {
        Environment.shared.tuistVariables[rawValue]
    }
    
    func envValue<T: ExpressibleByArgument>() -> T? {
        guard let envValueString else {
            return nil
        }
        return T(argument: envValueString)
    }
    
    func envArrayValue<T: ExpressibleByArgument>() -> [T] {
        guard let envValueString else {
            return []
        }
        return envValueString.split(separator: ",").compactMap { T(argument: String($0)) }
    }
}

extension ArgumentHelp {
    func withEnvKey(_ envKey: EnvKey) -> ArgumentHelp {
        var help = self
        help.abstract += " (env: \(envKey.rawValue))"
        return help
    }
}

// Argument Extensions
extension Argument {
    init<T>(
        wrappedValue: [T] = [],
        parsing parsingStrategy: ArgumentArrayParsingStrategy = .remaining,
        help: ArgumentHelp? = nil,
        completion: CompletionKind? = nil,
        envKey: EnvKey
    ) where T: ExpressibleByArgument, Value == [T] {
        self.init(
            wrappedValue: wrappedValue.isEmpty ? envKey.envArrayValue() : wrappedValue,
            parsing: parsingStrategy,
            help: help?.withEnvKey(envKey),
            completion: completion
        )
    }
    
    init(
        help: ArgumentHelp? = nil,
        envKey: EnvKey
    ) where Value: ExpressibleByArgument {
        let envValue: Value? = envKey.envValue()
        if let envValue {
            self.init(wrappedValue: envValue, help: help)
        } else {
            self.init(help: help)
        }
    }
    
    public init<T>(
        wrappedValue _value: Optional<T> = nil,
        help: ArgumentHelp? = nil,
        completion: CompletionKind? = nil,
        envKey: EnvKey
    ) where T: ExpressibleByArgument, Value == Optional<T> {
        self.init(
            wrappedValue: _value ?? envKey.envValue(),
            help: help?.withEnvKey(envKey),
            completion: completion
        )
    }
}

// Option Extensions
extension Option {
    public init<T>(
        wrappedValue _value: [T] = [],
        name: NameSpecification = .long,
        parsing parsingStrategy: ArrayParsingStrategy = .singleValue,
        help: ArgumentHelp? = nil,
        completion: CompletionKind? = nil,
        envKey: EnvKey
    ) where T: ExpressibleByArgument, Value == [T] {
        self.init(
            wrappedValue: _value.isEmpty ? envKey.envArrayValue() : _value,
            name: name,
            parsing: parsingStrategy,
            help: help?.withEnvKey(envKey),
            completion: completion
        )
    }
    
    public init<T>(
        wrappedValue _value: Optional<T> = nil,
        name: NameSpecification = .long,
        parsing parsingStrategy: SingleValueParsingStrategy = .next,
        help: ArgumentHelp? = nil,
        completion: CompletionKind? = nil,
        envKey: EnvKey
    ) where T: ExpressibleByArgument, Value == Optional<T> {
        self.init(
            wrappedValue: _value ?? envKey.envValue(),
            name: name,
            parsing: parsingStrategy,
            help: help?.withEnvKey(envKey),
            completion: completion
        )
    }
    
    init(
        wrappedValue _value: Value,
        name: NameSpecification = .long,
        parsing parsingStrategy: SingleValueParsingStrategy = .next,
        help: ArgumentHelp? = nil,
        completion: CompletionKind? = nil,
        envKey: EnvKey
    ) where Value: ExpressibleByArgument {
        let envValue: Value? = envKey.envValue()
        if let envValue {
            self.init(
                wrappedValue: envValue,
                name: name,
                parsing: parsingStrategy,
                help: help?.withEnvKey(envKey),
                completion: completion
            )
        } else {
            self.init(
                name: name,
                parsing: parsingStrategy,
                help: help?.withEnvKey(envKey),
                completion: completion
            )
        }
    }
    
    init(
        name: NameSpecification = .long,
        parsing parsingStrategy: SingleValueParsingStrategy = .next,
        help: ArgumentHelp? = nil,
        completion: CompletionKind? = nil,
        envKey: EnvKey
    ) where Value: ExpressibleByArgument {
        let envValue: Value? = envKey.envValue()
        if let envValue {
            self.init(
                wrappedValue: envValue,
                name: name,
                parsing: parsingStrategy,
                help: help?.withEnvKey(envKey),
                completion: completion
            )
        } else {
            self.init(
                name: name,
                parsing: parsingStrategy,
                help: help?.withEnvKey(envKey),
                completion: completion
            )
        }
    }
}

// Flag Extensions
extension Flag where Value == Bool {
    public init(
        wrappedValue: Bool,
        name: NameSpecification = .long,
        help: ArgumentHelp? = nil,
        envKey: EnvKey
    ) {
        if let envValue: Value = envKey.envValue() {
            self.init(
                wrappedValue: envValue,
                name: name,
                inversion: .prefixedNo,
                help: help?.withEnvKey(envKey)
            )
        } else {
            self.init(
                wrappedValue: wrappedValue,
                name: name,
                inversion: .prefixedNo,
                help: help?.withEnvKey(envKey)
            )
        }
    }
}
