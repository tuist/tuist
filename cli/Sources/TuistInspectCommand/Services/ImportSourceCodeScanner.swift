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
            try extractImports(from: sourceCode, language: language, context: nil)
        }

        /// Extract imports from a source file.
        ///
        /// When `context` is non-nil and the language is Swift, `#if` / `#elseif` / `#else` /
        /// `#endif` blocks are walked and `import` lines whose enclosing condition would not
        /// fire under the target's compilation context are skipped. This stops conditionally
        /// linked dependencies from being misreported as implicit imports for variants that
        /// don't declare them.
        func extractImports(
            from sourceCode: String,
            language: ProgrammingLanguage,
            context: CompilationConditionContext?
        ) throws -> Set<String> {
            switch language {
            case .swift:
                return try extractSwiftImports(from: sourceCode, context: context)
            case .objc:
                return try extract(from: sourceCode, language: .objc)
            }
        }

        private func extractSwiftImports(
            from sourceCode: String,
            context: CompilationConditionContext?
        ) throws -> Set<String> {
            let codeWithoutComments = try removeComments(from: sourceCode)
            let pattern = #"import\s+(?:struct\s+|enum\s+|class\s+|protocol\s+|func\s+|var\s+|let\s+|typealias\s+)?([\w]+)"#
            let regex = try NSRegularExpression(pattern: pattern, options: [])

            // Walk lines top-to-bottom, maintaining a stack of conditional-compilation
            // frames. `import` lines are only collected when every enclosing frame is active.
            var stack: [ConditionalFrame] = []
            var imports: Set<String> = []
            let parser = CompilationConditionParser()

            for rawLine in codeWithoutComments.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)

                if line.hasPrefix("#if ") || line == "#if" {
                    let expression = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    let active = evaluate(expression, parser: parser, context: context)
                    let parentActive = stack.allSatisfy(\.active)
                    stack.append(ConditionalFrame(active: parentActive && active, anyBranchActive: active))
                    continue
                }

                if line.hasPrefix("#elseif ") {
                    guard !stack.isEmpty else { continue }
                    let expression = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                    var frame = stack.removeLast()
                    let raw = evaluate(expression, parser: parser, context: context)
                    let active = !frame.anyBranchActive && raw
                    frame.active = (stack.allSatisfy(\.active)) && active
                    frame.anyBranchActive = frame.anyBranchActive || raw
                    stack.append(frame)
                    continue
                }

                if line == "#else" {
                    guard !stack.isEmpty else { continue }
                    var frame = stack.removeLast()
                    let active = !frame.anyBranchActive
                    frame.active = (stack.allSatisfy(\.active)) && active
                    frame.anyBranchActive = true
                    stack.append(frame)
                    continue
                }

                if line == "#endif" {
                    if !stack.isEmpty { stack.removeLast() }
                    continue
                }

                guard stack.allSatisfy(\.active) else { continue }

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

        private func evaluate(
            _ expression: String,
            parser: CompilationConditionParser,
            context: CompilationConditionContext?
        ) -> Bool {
            // No context = caller wants every branch counted (legacy behaviour).
            guard let context else { return true }
            do {
                let parsed = try parser.parse(expression)
                return CompilationConditionEvaluator.evaluate(parsed, in: context)
            } catch {
                // If we can't parse the expression, be conservative and treat it as
                // active so we don't silently drop a branch we don't understand.
                return true
            }
        }

        private struct ConditionalFrame {
            var active: Bool
            var anyBranchActive: Bool
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
