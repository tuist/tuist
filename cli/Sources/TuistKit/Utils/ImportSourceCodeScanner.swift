import Foundation

enum ProgrammingLanguage {
    case swift
    case objc
}

private struct Match {
    let module: String
    let range: Range<String.Index>
}

final class ImportSourceCodeScanner {
    func extractImports(from sourceCode: String, language: ProgrammingLanguage) throws -> Set<String> {
        switch language {
        case .swift:
            try extract(from: sourceCode, language: .swift)
        case .objc:
            try extract(from: sourceCode, language: .objc)
        }
    }

    private func extract(from code: String, language: ProgrammingLanguage) throws -> Set<String> {
        let pattern = switch language {
        case .swift:
            #"import\s+(?:struct\s+|enum\s+|class\s+)?([\w]+)"#
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
