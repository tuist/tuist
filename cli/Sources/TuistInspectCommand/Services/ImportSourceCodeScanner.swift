#if os(macOS)
    import Foundation

    enum ProgrammingLanguage {
        case swift
        case objc
    }

    struct ImportSourceCodeScanner {
        /// Compiled once at static-init time — Swift `Regex` literals build the
        /// automaton up front, so we cache them here rather than per-line.
        private static let swiftImportRegex =
            #/import\s+(?:struct\s+|enum\s+|class\s+|protocol\s+|func\s+|var\s+|let\s+|typealias\s+)?([\w]+)/#
        private static let objcImportRegex =
            #/@import\s+([A-Za-z_0-9]+)|#(?:import|include)\s+<([A-Za-z_0-9-]+)\//#
        private static let canImportConditionRegex =
            #/^canImport\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)$/#
        private static let commentRegex =
            #/\/\/.*?$|\/\*[\s\S]*?\*\//#.anchorsMatchLineEndings()
        private static let blankLineRegex =
            #/^\s*\n/#.anchorsMatchLineEndings()

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
                return extractSwiftImports(from: sourceCode, reachableModules: reachableModules)
            case .objc:
                return extractObjcImports(from: sourceCode)
            }
        }

        private func extractSwiftImports(
            from sourceCode: String,
            reachableModules: Set<String>?
        ) -> Set<String> {
            let codeWithoutComments = removeComments(from: sourceCode)

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

                for match in line.matches(of: Self.swiftImportRegex) {
                    let module = match.output.1.split(separator: ".").first.map(String.init) ?? String(match.output.1)
                    imports.insert(module)
                }
            }
            return imports
        }

        private func extractObjcImports(from sourceCode: String) -> Set<String> {
            let codeWithoutComments = removeComments(from: sourceCode)
            var imports: Set<String> = []
            for line in codeWithoutComments.components(separatedBy: .newlines) {
                for match in line.matches(of: Self.objcImportRegex) {
                    if let semantic = match.output.1 {
                        imports.insert(String(semantic))
                    } else if let header = match.output.2 {
                        imports.insert(String(header))
                    }
                }
            }
            return imports
        }

        /// True when the condition is exactly `canImport(X)` and `X` is not reachable
        /// from the current target. Anything else (compound expressions, negation,
        /// custom flags) returns `false` so the branch stays active.
        private func isDeadCanImport(_ condition: String, reachableModules: Set<String>?) -> Bool {
            guard let reachableModules,
                  let match = try? Self.canImportConditionRegex.wholeMatch(in: condition)
            else { return false }
            return !reachableModules.contains(String(match.output.1))
        }

        private struct Frame {
            var skipping: Bool
        }

        private func removeComments(from code: String) -> String {
            code.replacing(Self.commentRegex, with: "")
                .replacing(Self.blankLineRegex, with: "")
        }
    }
#endif
