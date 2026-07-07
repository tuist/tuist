import Foundation
import XCLogParser

final class SLFLexer {
    private static let header = "SLF"
    private static let typeDelimiters: Set<Character> = ["#", "%", "@", "\"", "^", "-", "(", "*"]
    private static let payloadCharacters: Set<Character> = ["a", "b", "c", "d", "e", "f", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]

    private let filePath: String
    private var classNames = [String]()

    init(filePath: String) {
        self.filePath = filePath
    }

    func tokenize(contents: String) throws -> [Token] {
        let scanner = SLFScanner(string: contents)

        guard scanner.scan(string: Self.header) else {
            throw XCLogParserError.invalidLogHeader(filePath)
        }

        var tokens = [Token]()
        while !scanner.isAtEnd {
            guard let logTokens = scanSLFType(scanner: scanner), !logTokens.isEmpty else {
                throw XCLogParserError.invalidLine(scanner.approximateLine)
            }
            tokens.append(contentsOf: logTokens)
        }

        return tokens
    }

    private func scanSLFType(scanner: SLFScanner) -> [Token]? {
        let payload = scanPayload(scanner: scanner)

        guard let tokenTypes = scanTypeDelimiter(scanner: scanner), !tokenTypes.isEmpty else {
            return nil
        }

        var tokens = [Token]()
        for tokenType in tokenTypes {
            guard let token = scanToken(scanner: scanner, payload: payload, tokenType: tokenType) else {
                return nil
            }
            tokens.append(token)
        }

        return tokens
    }

    private func scanPayload(scanner: SLFScanner) -> String {
        scanner.scanCharacters(from: Self.payloadCharacters) ?? ""
    }

    private func scanTypeDelimiter(scanner: SLFScanner) -> [TokenType]? {
        guard let delimiters = scanner.scanCharacters(from: Self.typeDelimiters) else {
            return nil
        }

        if delimiters.count > 1, delimiters.first == Character(TokenType.string.rawValue) {
            scanner.moveOffset(by: -(delimiters.count - 1))
            return [.string]
        }

        return delimiters.compactMap { character in
            TokenType(rawValue: String(character))
        }
    }

    private func scanToken(scanner: SLFScanner, payload: String, tokenType: TokenType) -> Token? {
        switch tokenType {
        case .int:
            return UInt64(payload).map(Token.int)
        case .className:
            guard let className = scanString(length: payload, scanner: scanner) else { return nil }
            classNames.append(className)
            return .className(className)
        case .classNameRef:
            guard let value = Int(payload), value > 0, value <= classNames.count else { return nil }
            return .classNameRef(classNames[value - 1])
        case .string:
            return scanString(length: payload, scanner: scanner).map(Token.string)
        case .double:
            return hexToDouble(payload).map(Token.double)
        case .null:
            return .null
        case .list:
            return Int(payload).map(Token.list)
        case .json:
            return scanString(length: payload, scanner: scanner).map(Token.json)
        }
    }

    private func scanString(length: String, scanner: SLFScanner) -> String? {
        guard let length = Int(length) else { return nil }
        return scanner.scanUTF16CodeUnits(count: length)
    }

    private func hexToDouble(_ input: String) -> Double? {
        guard let beValue = UInt64(input, radix: 16) else { return nil }
        return Double(bitPattern: beValue.byteSwapped)
    }
}

private final class SLFScanner {
    let string: String
    private(set) var offset: Int

    var isAtEnd: Bool {
        offset >= string.utf16.count
    }

    var approximateLine: String {
        let endOffset = min(offset + 21, string.utf16.count)
        guard let start = index(atUTF16Offset: offset), let end = index(atUTF16Offset: endOffset), start <= end else {
            return ""
        }
        return String(string[start..<end])
    }

    init(string: String) {
        self.string = string
        self.offset = 0
    }

    func scan(string value: String) -> Bool {
        guard let start = index(atUTF16Offset: offset), string[start...].hasPrefix(value) else { return false }
        offset += value.utf16.count
        return true
    }

    func scanCharacters(from allowedCharacters: Set<Character>) -> String? {
        var prefix = ""

        while !isAtEnd {
            guard let index = index(atUTF16Offset: offset) else { return nil }
            let character = string[index]
            guard allowedCharacters.contains(character) else { break }
            prefix.append(character)
            offset += character.utf16.count
        }

        return prefix
    }

    func scanUTF16CodeUnits(count: Int) -> String? {
        let endOffset = offset + count
        guard count >= 0,
              endOffset <= string.utf16.count,
              let start = index(atUTF16Offset: offset),
              let end = index(atUTF16Offset: endOffset)
        else {
            return nil
        }

        let result = String(string[start..<end])
        offset = endOffset
        return result
    }

    func moveOffset(by value: Int) {
        offset += value
    }

    private func index(atUTF16Offset utf16Offset: Int) -> String.Index? {
        guard utf16Offset >= 0,
              let utf16Index = string.utf16.index(
                string.utf16.startIndex,
                offsetBy: utf16Offset,
                limitedBy: string.utf16.endIndex
              )
        else {
            return nil
        }

        if utf16Index == string.utf16.endIndex {
            return string.endIndex
        }

        return String.Index(utf16Index, within: string)
    }
}
