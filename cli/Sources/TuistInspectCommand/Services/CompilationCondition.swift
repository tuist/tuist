#if os(macOS)
    import Foundation

    /// Represents a parsed Swift `#if` / `#elseif` compilation condition expression.
    ///
    /// Mirrors the subset of Swift's compilation directive grammar that affects which
    /// `import` lines a static analyzer should consider live for a given target. The
    /// goal is not full Swift compatibility, only enough to evaluate the expressions
    /// developers actually write at the top of files.
    enum CompilationCondition: Equatable {
        case literal(Bool)
        /// A bare flag identifier such as `DEBUG`, `BETA`, or `Live`.
        case flag(String)
        case canImport(String)
        case os(String)
        case arch(String)
        case targetEnvironment(String)
        case swift(VersionComparison)
        case compiler(VersionComparison)
        case hasFeature(String)
        case hasAttribute(String)
        indirect case not(CompilationCondition)
        indirect case and(CompilationCondition, CompilationCondition)
        indirect case or(CompilationCondition, CompilationCondition)

        struct VersionComparison: Equatable {
            enum Operator: String {
                case greaterThanOrEqual = ">="
                case lessThan = "<"
            }

            let `operator`: Operator
            let version: [Int]
        }
    }

    /// Inputs to the evaluator describing what a given target "is" at compile time.
    ///
    /// Multiple flag sets are supported because a single target compiles under several
    /// build configurations (Debug, Release, …) and `SWIFT_ACTIVE_COMPILATION_CONDITIONS`
    /// can differ per configuration. An `import` is considered live when it would fire
    /// under at least one configuration — that mirrors what the linker actually pulls
    /// in across CI matrix builds.
    struct CompilationConditionContext: Equatable {
        /// Active flags per build configuration.
        let flagSetsPerConfiguration: [Set<String>]
        /// `os(...)` checks succeed for any of these.
        let platforms: Set<String>
        /// `arch(...)` checks succeed for any of these.
        let architectures: Set<String>
        /// `targetEnvironment(...)` checks succeed for any of these.
        let targetEnvironments: Set<String>
        /// Modules reachable through the target's transitive declared dependencies.
        let reachableModules: Set<String>
        /// Used to evaluate `swift(>=X)` / `compiler(>=X)`. Defaults to an open-ended
        /// version high enough to satisfy any reasonable comparison.
        let swiftVersion: [Int]
        let compilerVersion: [Int]

        init(
            flagSetsPerConfiguration: [Set<String>] = [[]],
            platforms: Set<String> = [],
            architectures: Set<String> = [],
            targetEnvironments: Set<String> = [],
            reachableModules: Set<String> = [],
            swiftVersion: [Int] = [99, 0, 0],
            compilerVersion: [Int] = [99, 0, 0]
        ) {
            self.flagSetsPerConfiguration = flagSetsPerConfiguration.isEmpty ? [[]] : flagSetsPerConfiguration
            self.platforms = platforms
            self.architectures = architectures
            self.targetEnvironments = targetEnvironments
            self.reachableModules = reachableModules
            self.swiftVersion = swiftVersion
            self.compilerVersion = compilerVersion
        }
    }

    enum CompilationConditionParseError: Error, Equatable {
        case unexpectedToken(String)
        case unexpectedEnd
        case malformedVersion(String)
        case unknownDirective(String)
    }

    /// Recursive-descent parser for Swift `#if` condition expressions.
    ///
    /// Grammar (loosely):
    ///   expr   := or
    ///   or     := and ('||' and)*
    ///   and    := unary ('&&' unary)*
    ///   unary  := '!' unary | primary
    ///   primary:= '(' expr ')'
    ///           | identifier '(' arg ')'   // canImport/os/arch/swift/compiler/...
    ///           | identifier               // flag, or `true`/`false`
    struct CompilationConditionParser {
        func parse(_ source: String) throws -> CompilationCondition {
            var tokens = Tokenizer.tokenize(source)
            let expression = try parseOr(&tokens)
            if !tokens.isEmpty {
                throw CompilationConditionParseError.unexpectedToken(tokens[0].description)
            }
            return expression
        }

        private func parseOr(_ tokens: inout [Token]) throws -> CompilationCondition {
            var lhs = try parseAnd(&tokens)
            while case .or = tokens.first {
                tokens.removeFirst()
                let rhs = try parseAnd(&tokens)
                lhs = .or(lhs, rhs)
            }
            return lhs
        }

        private func parseAnd(_ tokens: inout [Token]) throws -> CompilationCondition {
            var lhs = try parseUnary(&tokens)
            while case .and = tokens.first {
                tokens.removeFirst()
                let rhs = try parseUnary(&tokens)
                lhs = .and(lhs, rhs)
            }
            return lhs
        }

        private func parseUnary(_ tokens: inout [Token]) throws -> CompilationCondition {
            if case .bang = tokens.first {
                tokens.removeFirst()
                return .not(try parseUnary(&tokens))
            }
            return try parsePrimary(&tokens)
        }

        private func parsePrimary(_ tokens: inout [Token]) throws -> CompilationCondition {
            guard let head = tokens.first else { throw CompilationConditionParseError.unexpectedEnd }
            switch head {
            case .leftParen:
                tokens.removeFirst()
                let inner = try parseOr(&tokens)
                guard case .rightParen = tokens.first else {
                    throw CompilationConditionParseError.unexpectedToken(tokens.first?.description ?? "<eof>")
                }
                tokens.removeFirst()
                return inner

            case let .identifier(name):
                tokens.removeFirst()
                if case .leftParen = tokens.first {
                    tokens.removeFirst()
                    let argument = try parseCallArgument(&tokens)
                    guard case .rightParen = tokens.first else {
                        throw CompilationConditionParseError.unexpectedToken(tokens.first?.description ?? "<eof>")
                    }
                    tokens.removeFirst()
                    return try buildCall(name: name, argument: argument)
                }

                switch name {
                case "true": return .literal(true)
                case "false": return .literal(false)
                default: return .flag(name)
                }

            default:
                throw CompilationConditionParseError.unexpectedToken(head.description)
            }
        }

        private func parseCallArgument(_ tokens: inout [Token]) throws -> CallArgument {
            guard let first = tokens.first else { throw CompilationConditionParseError.unexpectedEnd }
            switch first {
            case let .identifier(name):
                tokens.removeFirst()
                return .identifier(name)
            case .compareGreaterEqual, .compareLessThan:
                let op = tokens.removeFirst()
                guard case let .identifier(version) = tokens.first else {
                    throw CompilationConditionParseError.unexpectedToken(tokens.first?.description ?? "<eof>")
                }
                tokens.removeFirst()
                let parsed = try parseVersion(version)
                let comparator: CompilationCondition.VersionComparison.Operator = (op == .compareGreaterEqual)
                    ? .greaterThanOrEqual : .lessThan
                return .versionComparison(.init(operator: comparator, version: parsed))
            default:
                throw CompilationConditionParseError.unexpectedToken(first.description)
            }
        }

        private func buildCall(name: String, argument: CallArgument) throws -> CompilationCondition {
            switch (name, argument) {
            case let ("canImport", .identifier(value)): return .canImport(value)
            case let ("os", .identifier(value)): return .os(value)
            case let ("arch", .identifier(value)): return .arch(value)
            case let ("targetEnvironment", .identifier(value)): return .targetEnvironment(value)
            case let ("hasFeature", .identifier(value)): return .hasFeature(value)
            case let ("hasAttribute", .identifier(value)): return .hasAttribute(value)
            case let ("swift", .versionComparison(comparison)): return .swift(comparison)
            case let ("compiler", .versionComparison(comparison)): return .compiler(comparison)
            // Unknown function call — surface as a parse error so the caller can fall
            // back to "branch active". For implicit-dep detection this preserves the
            // signal: a directive we don't understand still gets its imports counted.
            default: throw CompilationConditionParseError.unknownDirective(name)
            }
        }

        private func parseVersion(_ raw: String) throws -> [Int] {
            let parts = raw.split(separator: ".").map(String.init)
            var components: [Int] = []
            for part in parts {
                guard let value = Int(part) else { throw CompilationConditionParseError.malformedVersion(raw) }
                components.append(value)
            }
            if components.isEmpty { throw CompilationConditionParseError.malformedVersion(raw) }
            return components
        }

        private enum CallArgument {
            case identifier(String)
            case versionComparison(CompilationCondition.VersionComparison)
        }
    }

    private enum Token: Equatable {
        case identifier(String)
        case leftParen, rightParen
        case and, or, bang
        case compareGreaterEqual, compareLessThan

        var description: String {
            switch self {
            case let .identifier(value): return value
            case .leftParen: return "("
            case .rightParen: return ")"
            case .and: return "&&"
            case .or: return "||"
            case .bang: return "!"
            case .compareGreaterEqual: return ">="
            case .compareLessThan: return "<"
            }
        }
    }

    private enum Tokenizer {
        // swiftlint:disable:next function_body_length
        static func tokenize(_ source: String) -> [Token] {
            var tokens: [Token] = []
            var index = source.startIndex
            while index < source.endIndex {
                let character = source[index]
                if character.isWhitespace {
                    index = source.index(after: index)
                    continue
                }
                switch character {
                case "(":
                    tokens.append(.leftParen)
                    index = source.index(after: index)
                case ")":
                    tokens.append(.rightParen)
                    index = source.index(after: index)
                case "!":
                    tokens.append(.bang)
                    index = source.index(after: index)
                case "&":
                    let next = source.index(after: index)
                    if next < source.endIndex, source[next] == "&" {
                        tokens.append(.and)
                        index = source.index(after: next)
                    } else {
                        index = source.index(after: index)
                    }
                case "|":
                    let next = source.index(after: index)
                    if next < source.endIndex, source[next] == "|" {
                        tokens.append(.or)
                        index = source.index(after: next)
                    } else {
                        index = source.index(after: index)
                    }
                case ">":
                    let next = source.index(after: index)
                    if next < source.endIndex, source[next] == "=" {
                        tokens.append(.compareGreaterEqual)
                        index = source.index(after: next)
                    } else {
                        index = source.index(after: index)
                    }
                case "<":
                    tokens.append(.compareLessThan)
                    index = source.index(after: index)
                default:
                    if character.isLetter || character == "_" || character.isNumber || character == "." {
                        var end = index
                        while end < source.endIndex {
                            let scalar = source[end]
                            if scalar.isLetter || scalar.isNumber || scalar == "_" || scalar == "." {
                                end = source.index(after: end)
                            } else {
                                break
                            }
                        }
                        tokens.append(.identifier(String(source[index ..< end])))
                        index = end
                    } else {
                        index = source.index(after: index)
                    }
                }
            }
            return tokens
        }
    }

    enum CompilationConditionEvaluator {
        /// Evaluate a condition against the target context.
        ///
        /// Returns `true` if the condition holds under at least one of the target's
        /// build configurations (i.e. any flag set in `flagSetsPerConfiguration`).
        static func evaluate(
            _ condition: CompilationCondition,
            in context: CompilationConditionContext
        ) -> Bool {
            context.flagSetsPerConfiguration.contains(where: { flagSet in
                evaluateOne(condition, flags: flagSet, context: context)
            })
        }

        private static func evaluateOne(
            _ condition: CompilationCondition,
            flags: Set<String>,
            context: CompilationConditionContext
        ) -> Bool {
            switch condition {
            case let .literal(value):
                return value
            case let .flag(name):
                return flags.contains(name)
            case let .canImport(module):
                return context.reachableModules.contains(module)
            case let .os(value):
                // When the target's platforms aren't known, do not block on os() —
                // assume the import may fire on at least one platform.
                return context.platforms.isEmpty || context.platforms.contains(value)
            case let .arch(value):
                return context.architectures.isEmpty || context.architectures.contains(value)
            case let .targetEnvironment(value):
                return context.targetEnvironments.isEmpty || context.targetEnvironments.contains(value)
            case let .swift(comparison):
                return compare(context.swiftVersion, comparison)
            case let .compiler(comparison):
                return compare(context.compilerVersion, comparison)
            case .hasFeature, .hasAttribute:
                // Conservative default: assume the feature/attribute is present so
                // imports gated on Swift evolution flags aren't dropped silently.
                return true
            case let .not(inner):
                return !evaluateOne(inner, flags: flags, context: context)
            case let .and(lhs, rhs):
                return evaluateOne(lhs, flags: flags, context: context)
                    && evaluateOne(rhs, flags: flags, context: context)
            case let .or(lhs, rhs):
                return evaluateOne(lhs, flags: flags, context: context)
                    || evaluateOne(rhs, flags: flags, context: context)
            }
        }

        private static func compare(_ lhs: [Int], _ comparison: CompilationCondition.VersionComparison) -> Bool {
            switch comparison.operator {
            case .greaterThanOrEqual:
                return lexicographicCompare(lhs, comparison.version) >= 0
            case .lessThan:
                return lexicographicCompare(lhs, comparison.version) < 0
            }
        }

        private static func lexicographicCompare(_ lhs: [Int], _ rhs: [Int]) -> Int {
            let count = max(lhs.count, rhs.count)
            for index in 0 ..< count {
                let leftComponent = index < lhs.count ? lhs[index] : 0
                let rightComponent = index < rhs.count ? rhs[index] : 0
                if leftComponent != rightComponent { return leftComponent - rightComponent }
            }
            return 0
        }
    }
#endif
