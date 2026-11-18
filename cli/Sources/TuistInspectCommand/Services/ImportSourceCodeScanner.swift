#if os(macOS)
    import Foundation

    enum ProgrammingLanguage {
        case swift
        case objc
    }

    /// A module imported by a source file, with the modules of the `#if canImport(X)` blocks the import is nested in.
    struct ScannedImport: Equatable, Sendable {
        let module: String
        let canImportConditions: [String]
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
            try extractImports(from: sourceCode, language: language, reachableModules: nil)
        }

        /// Extract imports from a source file.
        ///
        /// When `reachableModules` is non-nil and the language is Swift, `import` lines
        /// inside `#if canImport(X)` are skipped when `X` is not in the set. This stops
        /// conditionally linked dependencies from being misreported as implicit imports
        /// for variants that don't declare them — `canImport` is the exact same check
        /// the compiler runs at build time.
        ///
        /// Other `#if` shapes (custom flags, compound expressions, etc.) are treated as
        /// active, preserving current scanner behaviour for everything else.
        func extractImports(
            from sourceCode: String,
            language: ProgrammingLanguage,
            reachableModules: Set<String>?
        ) throws -> Set<String> {
            Self.imports(in: scanImports(from: sourceCode, language: language), reachableModules: reachableModules)
        }

        /// Scans a source file once, keeping the `canImport` conditions of every import, so that
        /// `imports(in:reachableModules:)` can resolve them for any target without scanning the file again.
        func scanImports(from sourceCode: String, language: ProgrammingLanguage) -> [ScannedImport] {
            switch language {
            case .swift:
                return extractSwiftImports(from: sourceCode)
            case .objc:
                return extractObjcImports(from: sourceCode)
            }
        }

        /// The modules of `scannedImports`, skipping the imports in `#if canImport(X)` blocks whose `X`
        /// is not in `reachableModules`. Nothing is skipped when `reachableModules` is nil.
        static func imports(in scannedImports: [ScannedImport], reachableModules: Set<String>?) -> Set<String> {
            Set(
                scannedImports.lazy
                    .filter { scannedImport in
                        !scannedImport.canImportConditions.contains { isDeadCanImport($0, reachableModules: reachableModules) }
                    }
                    .map(\.module)
            )
        }

        /// True when the module of a `canImport` condition is not reachable from the current target.
        /// Without `reachableModules`, every branch stays active.
        private static func isDeadCanImport(_ module: String, reachableModules: Set<String>?) -> Bool {
            guard let reachableModules else { return false }
            return !reachableModules.contains(module)
        }

        private func extractSwiftImports(from sourceCode: String) -> [ScannedImport] {
            let codeWithoutComments = removeComments(from: sourceCode)

            // Walk lines top-to-bottom, maintaining a stack of `#if` frames. A frame holds `X` for
            // `#if canImport(X)`, and nil for every other directive shape and once its `#elseif`/`#else`
            // branch starts: those branches stay active, which matches the legacy behaviour for those cases.
            var stack: [String?] = []
            var imports: [ScannedImport] = []

            for rawLine in codeWithoutComments.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)

                if line.hasPrefix("#if ") || line == "#if" {
                    let condition = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    stack.append(canImportModule(in: condition))
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

        /// `X` when the condition is exactly `canImport(X)`. Anything else (compound expressions,
        /// negation, custom flags) returns nil so the branch stays active.
        private func canImportModule(in condition: String) -> String? {
            captures(of: Self.canImportConditionRegex, in: condition).first
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
