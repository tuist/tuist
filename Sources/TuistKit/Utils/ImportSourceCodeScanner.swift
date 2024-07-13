import Foundation

enum ProgrammingLanguage {
    case swift
    case objc
}

final class ImportSourceCodeScanner {
    func extractImports(from sourceCode: String, language: ProgrammingLanguage) throws -> [String] {
        switch language {
        case .swift:
            try extractAllImportsSwift(from: sourceCode)
        case .objc:
            try extractAllImportsObjc(from: sourceCode)
        }
    }

    func extractAllImportsSwift(from text: String) throws -> [String] {
        let pattern = #"^\s*import\s+([\w\d_]+)\s*$"#

        let regex = try NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)

        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        let modules = matches.compactMap { match -> String? in
            if let range = Range(match.range(at: 1), in: text) {
                return String(text[range])
            }
            return nil
        }

        return modules
    }

    func extractAllImportsObjc(from text: String) throws -> [String] {
        let pattern = "@import\\s+([A-Za-z_0-9]+)|#(?:import|include)\\s+<([A-Za-z_0-9-]+)/"

        let regex = try NSRegularExpression(pattern: pattern, options: [])
        let matches = regex.matches(
            in: text,
            options: [],
            range: NSRange(
                location: 0,
                length: text.utf16.count
            )
        )

        var imports = [String]()

        for match in matches {
            var extracted: String?

            if let range = Range(match.range(at: 1), in: text) {
                extracted = String(text[range])
            } else if let range = Range(match.range(at: 2), in: text) {
                extracted = String(text[range])
            }

            if let extracted {
                imports.append(extracted)
            }
        }

        return imports
    }
}
