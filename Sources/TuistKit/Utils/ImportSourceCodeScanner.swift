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

    private func extractAllImportsSwift(from code: String) throws -> [String] {
        let pattern = #"import\s+(?:struct\s+|enum\s+|class\s+)?([\w]+)"#

        var modules: [String] = []

        let regex = try NSRegularExpression(pattern: pattern, options: [])

        let matches = regex.matches(
            in: code,
            options: [],
            range: NSRange(
                location: 0,
                length: code.utf16.count
            )
        )

        for match in matches {
            if let moduleRange = Range(match.range(at: 1), in: code) {
                let module = String(code[moduleRange])
                let topLevelModule = module.split(separator: ".").first.map(String.init)
                if let topLevelModule, !modules.contains(topLevelModule) {
                    modules.append(topLevelModule)
                }
            }
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

        return matches.compactMap { match in
            if let range = Range(match.range(at: 1), in: text) {
                return String(text[range])
            } else if let range = Range(match.range(at: 2), in: text) {
                return String(text[range])
            }
            return nil
        }
    }
}
