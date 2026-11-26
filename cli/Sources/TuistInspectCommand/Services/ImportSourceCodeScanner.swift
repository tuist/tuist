#if os(macOS)
    import Foundation

    enum ProgrammingLanguage {
        case swift
        case objc
    }

    /// Alternatives of required modules in a single `#if` condition. Each alternative is a conjunction.
    struct CanImportCondition: Equatable, Sendable {
        let alternatives: [[String]]
    }

    /// A module imported by a source file, with the `canImport` conditions of its enclosing blocks.
    struct ScannedImport: Equatable, Sendable {
        let module: String
        let canImportConditions: [CanImportCondition]
    }

    struct ImportSourceCodeScanner {
        // `NSRegularExpression` runs these patterns an order of magnitude faster than Swift `Regex`,
        // which matters when scanning every source file of large projects.
        // swiftlint:disable force_try
        private static let swiftImportRegex = try! NSRegularExpression(
            pattern: #"import\s+(?:struct\s+|enum\s+|class\s+|protocol\s+|func\s+|var\s+|let\s+|typealias\s+)?(\w+)"#
        )
        private static let objcImportRegex = try! NSRegularExpression(
            pattern: #"@import\s+([A-Za-z_0-9]+)|#(?:import|include)\s+<([A-Za-z_0-9-]+)/"#
        )
        private static let canImportConditionRegex = try! NSRegularExpression(
            pattern: #"^canImport\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)$"#
        )
        private static let commentRegex = try! NSRegularExpression(
            pattern: #"//.*?$|/\*[\s\S]*?\*/"#,
            options: .anchorsMatchLines
        )
        // swiftlint:enable force_try

        func extractImports(from sourceCode: String, language: ProgrammingLanguage) throws -> Set<String> {
            try extractImports(from: sourceCode, language: language, unreachableModules: nil)
        }

        /// Extract imports from a source file.
        ///
        /// When `unreachableModules` is non-nil and the language is Swift, `import` lines
        /// inside a `#if` containing only `canImport` checks joined by `&&` or `||` are
        /// skipped when the condition is false. A `canImport(X)` check is false only when `X`
        /// is in `unreachableModules`: the graph's modules the target can't reach. Checks of
        /// modules outside the graph, such as `UIKit` or `AppKit`, stay true. This stops
        /// conditionally linked dependencies from being misreported as implicit imports for
        /// variants that don't declare them.
        ///
        /// Other `#if` shapes (custom flags, parentheses, etc.) are treated as active.
        func extractImports(
            from sourceCode: String,
            language: ProgrammingLanguage,
            unreachableModules: Set<String>?
        ) throws -> Set<String> {
            Self.imports(in: scanImports(from: sourceCode, language: language), unreachableModules: unreachableModules)
        }

        /// Scans a source file once, keeping the `canImport` conditions of every import, so that
        /// `imports(in:unreachableModules:)` can resolve them for any target without scanning the file again.
        func scanImports(from sourceCode: String, language: ProgrammingLanguage) -> [ScannedImport] {
            switch language {
            case .swift:
                return extractSwiftImports(from: sourceCode)
            case .objc:
                return extractObjcImports(from: sourceCode)
            }
        }

        /// The modules of `scannedImports`, skipping imports with any false `canImport` condition.
        /// Nothing is skipped when `unreachableModules` is nil.
        static func imports(in scannedImports: [ScannedImport], unreachableModules: Set<String>?) -> Set<String> {
            Set(
                scannedImports.lazy
                    .filter { scannedImport in
                        !scannedImport.canImportConditions
                            .contains { isDeadCanImport($0, unreachableModules: unreachableModules) }
                    }
                    .map(\.module)
            )
        }

        /// True when every alternative requires an unreachable module. Without `unreachableModules`,
        /// every branch stays active.
        private static func isDeadCanImport(_ condition: CanImportCondition, unreachableModules: Set<String>?) -> Bool {
            guard let unreachableModules else { return false }
            return condition.alternatives.allSatisfy { alternative in
                alternative.contains { unreachableModules.contains($0) }
            }
        }

        private func extractSwiftImports(from sourceCode: String) -> [ScannedImport] {
            let codeWithoutComments = removeComments(from: sourceCode)

            // Each frame holds a condition, or nil for unsupported conditions
            // and `#elseif`/`#else` branches, which stay active.
            var stack: [CanImportCondition?] = []
            var imports: [ScannedImport] = []

            for rawLine in codeWithoutComments.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)

                if line.hasPrefix("#if ") || line == "#if" {
                    let condition = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    stack.append(canImportCondition(in: condition))
                    continue
                }

                // For #elseif and #else we don't try to be clever — once we leave the
                // canImport branch we drop back to "active" and let the rest of the
                // block be scanned normally.
                if line.hasPrefix("#elseif ") || line == "#else" {
                    if !stack.isEmpty { stack[stack.count - 1] = nil }
                    continue
                }

                if line == "#endif" {
                    if !stack.isEmpty { stack.removeLast() }
                    continue
                }

                let modules = captures(of: Self.swiftImportRegex, in: line)
                if !modules.isEmpty {
                    let conditions = stack.compactMap { $0 }
                    imports.append(contentsOf: modules.map { ScannedImport(module: $0, canImportConditions: conditions) })
                }
            }
            return imports
        }

        private func extractObjcImports(from sourceCode: String) -> [ScannedImport] {
            let codeWithoutComments = removeComments(from: sourceCode)
            return codeWithoutComments.components(separatedBy: .newlines).flatMap { line in
                captures(of: Self.objcImportRegex, in: line).map { ScannedImport(module: $0, canImportConditions: []) }
            }
        }

        /// Parses bare `canImport` checks, respecting the higher precedence of `&&` over `||`.
        /// Unsupported or malformed expressions stay active.
        private func canImportCondition(in condition: String) -> CanImportCondition? {
            var alternatives: [[String]] = []
            for alternative in condition.components(separatedBy: "||") {
                let terms = alternative.components(separatedBy: "&&")
                let modules = terms.compactMap { term in
                    captures(of: Self.canImportConditionRegex, in: term.trimmingCharacters(in: .whitespaces)).first
                }
                guard modules.count == terms.count else { return nil }
                alternatives.append(modules)
            }
            return CanImportCondition(alternatives: alternatives)
        }

        /// The first participating capture group of every match of `regex` in `string`.
        private func captures(of regex: NSRegularExpression, in string: String) -> [String] {
            let nsString = string as NSString
            return regex.matches(in: string, range: NSRange(location: 0, length: nsString.length)).compactMap { match in
                (1 ..< match.numberOfRanges).lazy
                    .map { match.range(at: $0) }
                    .first { $0.location != NSNotFound }
                    .map(nsString.substring(with:))
            }
        }

        private func removeComments(from code: String) -> String {
            Self.commentRegex.stringByReplacingMatches(
                in: code,
                range: NSRange(location: 0, length: (code as NSString).length),
                withTemplate: ""
            )
        }
    }
#endif
