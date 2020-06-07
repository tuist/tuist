import Foundation

extension String {
    // swiftlint:disable:next force_try
    private static let whitespaceRegularExpression = try! NSRegularExpression(pattern: "\\s")

    public var escapingWhitespaces: String {
        String.whitespaceRegularExpression.stringByReplacingMatches(
            in: self,
            range: NSRange(startIndex..., in: self),
            withTemplate: "\\\\$0"
        ).replacingOccurrences(of: "\0", with: "␀")
    }

    public func chomp(separator: String? = nil) -> String {
        func scrub(_ separator: String) -> String {
            var e = endIndex
            while String(self[startIndex ..< e]).hasSuffix(separator), e > startIndex {
                e = index(before: e)
            }
            return String(self[startIndex ..< e])
        }

        if let separator = separator {
            return scrub(separator)
        } else if hasSuffix("\r\n") {
            return scrub("\r\n")
        } else if hasSuffix("\n") {
            return scrub("\n")
        } else {
            return self
        }
    }

    public func chuzzle() -> String? {
        var cc = self

        loop: while true {
            switch cc.first {
            case nil:
                return nil
            case "\n"?, "\r"?, " "?, "\t"?, "\r\n"?:
                cc = String(cc.dropFirst())
            default:
                break loop
            }
        }

        loop: while true {
            switch cc.last {
            case nil:
                return nil
            case "\n"?, "\r"?, " "?, "\t"?, "\r\n"?:
                cc = String(cc.dropLast())
            default:
                break loop
            }
        }

        return String(cc)
    }

    public func nsRange(from range: Range<String.Index>) -> NSRange? {
        guard
            let from = range.lowerBound.samePosition(in: utf16),
            let to = range.upperBound.samePosition(in: utf16) else { return nil }

        return NSRange(location: utf16.distance(from: utf16.startIndex, to: from),
                       length: utf16.distance(from: from, to: to))
    }

    public func capitalizingFirstLetter() -> String {
        prefix(1).capitalized + dropFirst()
    }

    public mutating func capitalizeFirstLetter() {
        self = capitalizingFirstLetter()
    }
}

private func inShellWhitelist(_ codeUnit: UInt8) -> Bool {
    switch codeUnit {
    case UInt8(ascii: "a") ... UInt8(ascii: "z"),
         UInt8(ascii: "A") ... UInt8(ascii: "Z"),
         UInt8(ascii: "0") ... UInt8(ascii: "9"),
         UInt8(ascii: "-"),
         UInt8(ascii: "_"),
         UInt8(ascii: "/"),
         UInt8(ascii: ":"),
         UInt8(ascii: "@"),
         UInt8(ascii: "%"),
         UInt8(ascii: "+"),
         UInt8(ascii: "="),
         UInt8(ascii: "."),
         UInt8(ascii: ","):
        return true
    default:
        return false
    }
}

extension String {
    /// Creates a shell escaped string. If the string does not need escaping, returns the original string.
    /// Otherwise escapes using single quotes. For example:
    /// hello -> hello, hello$world -> 'hello$world', input A -> 'input A'
    ///
    /// - Returns: Shell escaped string.
    func shellEscaped() -> String {
        // If all the characters in the string are in whitelist then no need to escape.
        guard let pos = utf8.firstIndex(where: { !inShellWhitelist($0) }) else {
            return self
        }

        // If there are no single quotes then we can just wrap the string around single quotes.
        guard let singleQuotePos = utf8[pos...].firstIndex(of: UInt8(ascii: "'")) else {
            return "'" + self + "'"
        }

        // Otherwise iterate and escape all the single quotes.
        var newString = "'" + String(self[..<singleQuotePos])

        for char in self[singleQuotePos...] {
            if char == "'" {
                newString += "'\\''"
            } else {
                newString += String(char)
            }
        }

        newString += "'"

        return newString
    }

    /// Shell escapes the current string. This method is mutating version of shellEscaped().
    mutating func shellEscape() {
        self = shellEscaped()
    }
}
