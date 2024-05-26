import Foundation
import ArgumentParser

public enum EnvKey: String {
    // Specific to PluginCommand
    case pluginBuildTests
    case pluginShowBinPath
    case pluginTargets
    case pluginProducts
    case pluginTask
    case pluginArguments
    
    // Specific to BuildOptions
    case buildSchemes
    case buildGenerate
    case buildClean
    case buildPath
    case buildDevice
    case buildPlatform
    case buildOs
    case buildRosetta
    case buildConfiguration
    case buildOutputPath
    case buildDerivedDataPath
    case buildGenerateOnly
    
    // Specific to CleanCommand
    case cleanCategories
    case cleanPath
    
    // Specific to DumpCommand
    case dumpPath
    case dumpManifest
    
    case editOnlyCurrentDirectory
    
    // Specific to MigrationCommands
    case migrationXcodeprojPath
    case migrationTarget
    case migrationXcconfigPath
    
    // Specific to GenerateCommand
    case generatePath
    case generateOpen
    
    // Specific to GraphCommand
    case graphSkipTarget
    case graphSkipExternalDependencies
    case graphPlatform
    case graphFormat
    case graphNoOpen
    case graphLayoutAlgorithm
    case graphTargets
    case graphPath
    case graphOutputPath

    
    // InitCommand
    case initPlatform
    case initPath
    case initName
    case initTemplate
    
    // InstallCommand
    case installPath
    case installUpdate
    
    // ListCommand
    case listJson
    case listPath
    
    // RunCommand
    case runGenerate
    case runClean
    case runPath
    case runConfiguration
    case runDevice
    case runOs
    case runRosetta
    case runScheme
    case runArguments
    
    // ScaffoldCommand
    case scaffoldJson
    case scaffoldPath
    case scaffoldTemplate
    
    // TestCommand
    case testScheme
    case testClean
    case testPath
    case testDevice
    case testPlatform
    case testOs
    case testRosetta
    case testConfiguration
    case testSkipUiTests
    case testResultBundlePath
    case testDerivedDataPath
    case testRetryCount
    case testPlan
    case testTargets
    case testSkipTestTargets
    case testFilterConfigurations
    case testSkipConfigurations
    case testGenerateOnly
}

extension EnvKey {
    var envKey: String {
        rawValue.reduce(into: "TUIST_") { result, character in
            if character.isUppercase {
                result.append("_")
            }
            result.append(character)
        }.uppercased()
    }
    
    var envValueString: String? {
        ProcessInfo.processInfo.environment[envKey]
    }
    
    func envValue<T: ExpressibleByArgument>() -> T? {
        guard let envValueString else {
            return nil
        }
        return T.init(argument: envValueString)

    }
    
    func envArrayValue<T: ExpressibleByArgument>() -> [T] {
        guard let envValueString else {
            return []
        }
        return envValueString.split(separator: ",").compactMap { T.init(argument: String($0)) }
    }
}

extension Flag where Value == Bool {
    public init(
        wrappedValue: Bool,
        name: NameSpecification = .long,
        help: ArgumentHelp? = nil,
        envKey: EnvKey
    ) {
        let envValue: Bool = envKey.envValue() ?? false
        self.init(
            wrappedValue: envValue || wrappedValue,
            name: name,
            inversion: .prefixedNo,
            help: help
        )
    }
}

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
            help: help,
            completion: completion
        )
    }
}

extension Argument where Value: ExpressibleByArgument {
    init(
        help: ArgumentHelp? = nil,
        envKey: EnvKey
    ) {
        let envValue: Value? = envKey.envValue()
        if let envValue {
            self.init(wrappedValue: envValue, help: help)
        } else {
            self.init(help: help)
        }
    }
}

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
            help: help,
            completion: completion
        )
    }
}

extension Option {
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
            help: help,
            completion: completion
        )
    }
}

extension Option where Value: ExpressibleByArgument {
    init(
        wrappedValue _value: Value,
        name: NameSpecification = .long,
        parsing parsingStrategy: SingleValueParsingStrategy = .next,
        help: ArgumentHelp? = nil,
        completion: CompletionKind? = nil,
        envKey: EnvKey
    ) {
        let envValue: Value? = envKey.envValue()
        if let envValue {
            self.init(wrappedValue: envValue, name: name, parsing: parsingStrategy, help: help, completion: completion)
        } else {
            self.init(wrappedValue: _value, name: name, parsing: parsingStrategy, help: help, completion: completion)
        }
    }
}

extension Argument {
    public init<T>(
        wrappedValue _value: Optional<T> = nil,
        help: ArgumentHelp? = nil,
        completion: CompletionKind? = nil,
        envKey: EnvKey
    ) where T: ExpressibleByArgument, Value == Optional<T> {
        self.init(
            wrappedValue: _value ?? envKey.envValue(),
            help: help,
            completion: completion
        )
    }
}

