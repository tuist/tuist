#if os(macOS)
    import Foundation

    enum ProgrammingLanguage {
        case swift
        case objc
    }

    private struct Match {
        let module: String
        let range: Range<String.Index>
    }

    struct ImportSourceCodeScanner {
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
            switch language {
            case .swift:
                return try extractSwiftImports(from: sourceCode, reachableModules: reachableModules)
            case .objc:
                return try extract(from: sourceCode, language: .objc)
            }
        }

        private func extractSwiftImports(
            from sourceCode: String,
            reachableModules: Set<String>?
        ) throws -> Set<String> {
            let codeWithoutComments = try removeComments(from: sourceCode)
            let pattern = #"import\s+(?:struct\s+|enum\s+|class\s+|protocol\s+|func\s+|var\s+|let\s+|typealias\s+)?([\w]+)"#
            let regex = try NSRegularExpression(pattern: pattern, options: [])

            // Walk lines top-to-bottom, maintaining a stack of `#if` frames. A frame is
            // "skipping" only when its enclosing `#if canImport(X)` references a module
            // not in `reachableModules`. Every other directive shape leaves the frame
            // active, which matches the legacy behaviour for those cases.
            var stack: [Frame] = []
            var imports: Set<String> = []

            for rawLine in codeWithoutComments.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)

                if line.hasPrefix("#if ") || line == "#if" {
                    let condition = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    let parentSkipping = stack.last?.skipping ?? false
                    let skipping = parentSkipping || isDeadCanImport(condition, reachableModules: reachableModules)
                    stack.append(Frame(skipping: skipping))
                    continue
                }

                // For #elseif and #else we don't try to be clever — once we leave the
                // canImport branch we drop back to "active" and let the rest of the
                // block be scanned normally.
                if line.hasPrefix("#elseif ") || line == "#else" {
                    if !stack.isEmpty {
                        stack.removeLast()
                        let parentSkipping = stack.last?.skipping ?? false
                        stack.append(Frame(skipping: parentSkipping))
                    }
                    continue
                }

                if line == "#endif" {
                    if !stack.isEmpty { stack.removeLast() }
                    continue
                }

                if stack.last?.skipping == true { continue }

                let range = NSRange(location: 0, length: line.utf16.count)
                let matches = regex.matches(in: line, options: [], range: range)
                for match in matches {
                    if let found = processMatchSwift(match: match, line: line) {
                        imports.insert(found.module)
                    }
                }
            }
            return imports
        }

        /// True when the condition is exactly `canImport(X)` and `X` is not reachable
        /// from the current target. Anything else (compound expressions, negation,
        /// custom flags) returns `false` so the branch stays active.
        private func isDeadCanImport(_ condition: String, reachableModules: Set<String>?) -> Bool {
            guard let reachableModules else { return false }
            let pattern = #"^canImport\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)$"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
                  let match = regex.firstMatch(
                      in: condition,
                      options: [],
                      range: NSRange(location: 0, length: condition.utf16.count)
                  ),
                  let moduleRange = Range(match.range(at: 1), in: condition)
            else { return false }
            let module = String(condition[moduleRange])
            return !reachableModules.contains(module)
        }

        private struct Frame {
            var skipping: Bool
        }

        private func extract(from code: String, language: ProgrammingLanguage) throws -> Set<String> {
            let pattern = switch language {
            case .swift:
                #"import\s+(?:struct\s+|enum\s+|class\s+|protocol\s+|func\s+|var\s+|let\s+|typealias\s+)?([\w]+)"#
            case .objc:
                "@import\\s+([A-Za-z_0-9]+)|#(?:import|include)\\s+<([A-Za-z_0-9-]+)/"
            }

            let codeWithoutComments = try removeComments(from: code)

            let regex = try NSRegularExpression(pattern: pattern, options: [])

            return Set(
                codeWithoutComments
                    .components(separatedBy: .newlines)
                    .compactMap { line in
                        let range = NSRange(location: 0, length: line.utf16.count)
                        let matches = regex.matches(in: line, options: [], range: range)
                        return matches.compactMap { match in
                            let foundMatch = switch language {
                            case .swift:
                                processMatchSwift(match: match, line: line)
                            case .objc:
                                processMatchObjc(match: match, line: line)
                            }

                            return foundMatch?.module
                        }
                    }
                    .flatMap { $0 }
            )
        }

        private func processMatchSwift(match: NSTextCheckingResult, line: String) -> Match? {
            guard let moduleRange = Range(match.range(at: 1), in: line),
                  let foundModule = String(line[moduleRange]).split(separator: ".").first.map(String.init) else { return nil }
            return Match(
                module: foundModule,
                range: moduleRange
            )
        }

        private func processMatchObjc(match: NSTextCheckingResult, line: String) -> Match? {
            if let range = Range(match.range(at: 1), in: line) {
                return Match(
                    module: String(line[range]),
                    range: range
                )
            } else if let range = Range(match.range(at: 2), in: line) {
                return Match(
                    module: String(line[range]),
                    range: range
                )
            }
            return nil
        }

        private func removeComments(from code: String) throws -> String {
            let regexPattern = #"//.*?$|/\*[\s\S]*?\*/"#
            let regex = try NSRegularExpression(pattern: regexPattern, options: [.anchorsMatchLines])
            let range = NSRange(location: 0, length: code.count)

            return regex
                .stringByReplacingMatches(in: code, options: [], range: range, withTemplate: "")
                .replacingOccurrences(of: #"(?m)^\s*\n"#, with: "", options: .regularExpression)
        }
    }
#endif
