import ArgumentParser
import Foundation
import TuistSupport

extension Option {
    public init<T>(
        wrappedValue value: [T] = [],
        name: NameSpecification = .long,
        parsing parsingStrategy: ArrayParsingStrategy = .singleValue,
        help: ArgumentHelp? = nil,
        completion: CompletionKind? = nil,
        envKey: EnvKey
    ) where T: ExpressibleByArgument, Value == [T] {
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
                wrappedValue: value,
                name: name,
                parsing: parsingStrategy,
                help: help?.withEnvKey(envKey),
                completion: completion
            )
        }
    }

    public init<T>(
        name: NameSpecification = .long,
        parsing parsingStrategy: SingleValueParsingStrategy = .next,
        help: ArgumentHelp? = nil,
        completion: CompletionKind? = nil,
        envKey: EnvKey
    ) where T: ExpressibleByArgument, Value == T? {
        if let value: T = envKey.envValue() {
            self.init(
                wrappedValue: value,
                parsing: parsingStrategy,
                help: help?.withEnvKey(envKey),
                completion: completion
            ) { argument in
                T(argument: argument)
            }
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
        wrappedValue value: Value,
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
                wrappedValue: value,
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

// Argument Extensions
extension Argument {
    init<T>(
        wrappedValue value: [T] = [],
        parsing parsingStrategy: ArgumentArrayParsingStrategy = .remaining,
        help: ArgumentHelp? = nil,
        completion: CompletionKind? = nil,
        envKey: EnvKey
    ) where T: ExpressibleByArgument, Value == [T] {
        let envValue: Value? = envKey.envValue()
        if let envValue {
            self.init(
                wrappedValue: envValue,
                parsing: parsingStrategy,
                help: help?.withEnvKey(envKey),
                completion: completion
            )
        } else {
            self.init(
                wrappedValue: value,
                parsing: parsingStrategy,
                help: help?.withEnvKey(envKey),
                completion: completion
            )
        }
    }

    init(
        help: ArgumentHelp? = nil,
        completion: CompletionKind? = nil,
        envKey: EnvKey
    ) where Value: ExpressibleByArgument {
        let envValue: Value? = envKey.envValue()
        if let envValue {
            self.init(wrappedValue: envValue, help: help?.withEnvKey(envKey), completion: completion)
        } else {
            self.init(help: help?.withEnvKey(envKey), completion: completion)
        }
    }

    init(
        wrappedValue value: Value,
        help: ArgumentHelp? = nil,
        envKey: EnvKey
    ) where Value: ExpressibleByArgument {
        let envValue: Value? = envKey.envValue()
        if let envValue {
            self.init(wrappedValue: envValue, help: help?.withEnvKey(envKey))
        } else {
            self.init(wrappedValue: value, help: help?.withEnvKey(envKey))
        }
    }

    public init<T>(
        help: ArgumentHelp? = nil,
        completion: CompletionKind? = nil,
        envKey: EnvKey
    ) where T: ExpressibleByArgument, Value == T? {
        if let value: T = envKey.envValue() {
            self.init(
                wrappedValue: value,
                help: help?.withEnvKey(envKey),
                completion: completion
            ) { argument in
                T(argument: argument)
            }
        } else {
            self.init(
                help: help?.withEnvKey(envKey),
                completion: completion
            )
        }
    }
}

extension ArgumentHelp {
    func withEnvKey(_ envKey: EnvKey) -> ArgumentHelp {
        var help = self
        help.abstract += " (env: \(envKey.rawValue))"
        return help
    }
}
