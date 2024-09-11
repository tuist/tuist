import Foundation

enum ProgrammingLanguage {
    case swift
    case objc
}

struct Match {
    let module: String
    let range: Range<String.Index>
}

final class ImportSourceCodeScanner {
    func extractImports(from sourceCode: String, language: ProgrammingLanguage) throws -> [String] {
        switch language {
        case .swift:
            try extract(from: sourceCode, language: .swift)
        case .objc:
            try extract(from: sourceCode, language: .objc)
        }
    }

    private func extract(from code: String, language: ProgrammingLanguage) throws -> [String] {
        let pattern = switch language {
        case .swift:
            #"import\s+(?:struct\s+|enum\s+|class\s+)?([\w]+)"#
        case .objc:
            "@import\\s+([A-Za-z_0-9]+)|#(?:import|include)\\s+<([A-Za-z_0-9-]+)/"
        }

        var codeWithoutComments = CommentsRemover.removeComments(from: code)

        var result: [String] = []

        let regex = try NSRegularExpression(pattern: pattern, options: [])

        let lines = codeWithoutComments.components(separatedBy: .newlines)

        for line in lines {
            let range = NSRange(location: 0, length: line.utf16.count)
            let matches = regex.matches(in: line, options: [], range: range)

            for match in matches {
                let match = switch language {
                case .swift:
                    processMatchSwift(match: match, line: line)
                case .objc:
                    processMatchObjc(match: match, line: line)
                }
                if let match {
                    if !result.contains(where: { $0 == match.module }) {
                        result.append(match.module)
                    }
                }
            }
        }
        return result
    }

    private func processMatchSwift(match: NSTextCheckingResult, line: String) -> Match? {
        var module: Match?
        if let moduleRange = Range(match.range(at: 1), in: line),
           let foundModule = String(line[moduleRange]).split(separator: ".").first.map(String.init)
        {
            module = Match(
                module: foundModule,
                range: moduleRange
            )
        }
        return module
    }

    func processMatchObjc(match: NSTextCheckingResult, line: String) -> Match? {
        var result: Match?
        if let range = Range(match.range(at: 1), in: line) {
            result = Match(
                module: String(line[range]),
                range: range
            )
        } else if let range = Range(match.range(at: 2), in: line) {
            result = Match(
                module: String(line[range]),
                range: range
            )
        }
        return result
    }
}
