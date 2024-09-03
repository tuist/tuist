import Foundation

enum ProgrammingLanguage {
    case swift
    case objc
}

struct FoundImport: Equatable {
    let module: String
    let line: Int
}

final class ImportSourceCodeScanner {
    func extractImports(from sourceCode: String, language: ProgrammingLanguage) throws -> [FoundImport] {
        switch language {
        case .swift:
            try extractAllImportsSwift(from: sourceCode)
        case .objc:
            try extractAllImportsObjc(from: sourceCode)
        }
    }

    private func extractAllImportsSwift(from code: String) throws -> [FoundImport] {
        let pattern = #"import\s+(?:struct\s+|enum\s+|class\s+)?([\w]+)"#

        var result: [FoundImport] = []

        let regex = try NSRegularExpression(pattern: pattern, options: [])

        let lines = code.components(separatedBy: .newlines)

        for (lineNumber, line) in lines.enumerated() {
            let range = NSRange(location: 0, length: line.utf16.count)
            let matches = regex.matches(in: line, options: [], range: range)

            for match in matches {
                if let moduleRange = Range(match.range(at: 1), in: line) {
                    let module = String(line[moduleRange])
                    let topLevelModule = module.split(separator: ".").first.map(String.init)
                    if let topLevelModule, !result.contains(where: { $0.module == topLevelModule }) {
                        result.append(FoundImport(
                            module: topLevelModule,
                            line: lineNumber + 1
                        ))
                    }
                }
            }
        }
        return result
    }

    func extractAllImportsObjc(from text: String) throws -> [FoundImport] {
        let pattern = #"@import\s+([A-Za-z_0-9]+)|#(?:import|include)\s+<([A-Za-z_0-9-]+)"#

        var result: [FoundImport] = []

        let regex = try NSRegularExpression(pattern: pattern, options: [])

        // Split the text into lines
        let lines = text.components(separatedBy: .newlines)

        // Iterate over each line to find matches
        for (lineNumber, line) in lines.enumerated() {
            let range = NSRange(location: 0, length: line.utf16.count)
            let matches = regex.matches(in: line, options: [], range: range)

            for match in matches {
                var module: String?
                if let range = Range(match.range(at: 1), in: line) {
                    module = String(line[range])
                } else if let range = Range(match.range(at: 2), in: line) {
                    module = String(line[range])
                }

                if let module, !result.contains(where: { $0.module == module }) {
                    result.append(FoundImport(
                        module: module, line: lineNumber + 1
                    ))
                }
            }
        }

        return result
    }
}
