import Foundation

enum ProgrammingLanguage {
    case swift
    case objc
}

enum Comment {
    case singleLineComment(from: Int)
    case partialOneLineComment(from: Int, to: Int)
    case multilineCommentOpen(from: Int)
    case multilineCommentClose(from: Int)
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

        var result: [String] = []

        let regex = try NSRegularExpression(pattern: pattern, options: [])

        let lines = code.components(separatedBy: .newlines)

        var multilineCommentStarted = false

        for line in lines {
            let comments = findComments(line: line)
            let range = NSRange(location: 0, length: line.utf16.count)
            let matches = regex.matches(in: line, options: [], range: range)

            if multilineCommentStarted, !comments.contains(where: { comment in
                if case .multilineCommentClose = comment { return true }
                return false
            }) {
                continue
            }

            for match in matches {
                let match = switch language {
                case .swift:
                    processMatchSwift(match: match, line: line)
                case .objc:
                    processMatchObjc(match: match, line: line)
                }
                if let match {
                    let importStart = line.distance(from: line.startIndex, to: match.range.lowerBound)
                    let importEnd = line.distance(from: line.startIndex, to: match.range.upperBound)

                    var skip = multilineCommentStarted
                    for comment in comments {
                        switch comment {
                        case let .singleLineComment(from: from):
                            skip = importStart > from
                        case let .partialOneLineComment(from: from, to: to):
                            skip = importStart > from && importStart < importEnd && importEnd < to
                        case let .multilineCommentOpen(from: from):
                            skip = importStart > from
                        case let .multilineCommentClose(from: from):
                            skip = importStart < from
                        }
                    }

                    if skip { continue }

                    if !result.contains(where: { $0 == match.module }) {
                        result.append(match.module)
                    }
                }
            }
            for comment in comments {
                switch comment {
                case .singleLineComment, .partialOneLineComment: break
                case .multilineCommentOpen:
                    multilineCommentStarted = true
                case .multilineCommentClose:
                    multilineCommentStarted = false
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

    private func findComments(line: String) -> [Comment] {
        let singleLineCommentIndex = line.indicesOf(string: "//").first
        var openMultilineCommentIndices = line.indicesOf(string: "/*").sorted().filter {
            if let singleLineCommentIndex {
                return singleLineCommentIndex > $0
            }
            return true
        }
        var closeMultilineCommentIndices = line.indicesOf(string: "*/").sorted().filter {
            if let singleLineCommentIndex {
                return singleLineCommentIndex > $0
            }
            return true
        }

        var comments = [Comment]()

        while let closeComment = openMultilineCommentIndices.first,
              let openComment = closeMultilineCommentIndices.first
        {
            comments.append(Comment.partialOneLineComment(from: openComment, to: closeComment))
            openMultilineCommentIndices.removeFirst()
            closeMultilineCommentIndices.removeFirst()
        }

        if let openComment = openMultilineCommentIndices.first {
            comments.append(.multilineCommentOpen(from: openComment))
        }

        if let closeComment = closeMultilineCommentIndices.first {
            comments.append(.multilineCommentClose(from: closeComment))
        }

        if let terminatedComment = singleLineCommentIndex {
            comments.append(.singleLineComment(from: terminatedComment))
        }

        return comments
    }
}

extension String {
    fileprivate func indicesOf(string: String) -> [Int] {
        var indices = [Int]()
        var searchStartIndex = startIndex

        while searchStartIndex < endIndex,
              let range = range(of: string, range: searchStartIndex ..< endIndex),
              !range.isEmpty
        {
            let index = distance(from: startIndex, to: range.lowerBound)
            indices.append(index)
            searchStartIndex = range.upperBound
        }

        return indices
    }
}
