import Foundation

/// Demangles the Rust symbols `llvm-cov` names functions by, as `rustc-demangle`'s alternate form prints them
/// (no hashes or disambiguators): v0 (`_R…`, the default since Rust 1.95) and legacy (`_ZN…E`). A function's
/// coverage name may carry LLVM's `<file>;` prefix for local symbols. Names it cannot parse come back as given.
enum CargoSymbol {
    static func demangle(_ name: String) -> String {
        var symbol = Substring(name)
        if let separator = symbol.lastIndex(where: { $0 == ";" || $0 == ":" }) {
            symbol = symbol[symbol.index(after: separator)...]
        }
        // Mach-O symbols carry an extra leading underscore.
        if symbol.hasPrefix("__R") || symbol.hasPrefix("__ZN") { symbol = symbol.dropFirst() }
        if symbol.hasPrefix("_R") {
            var parser = V0(Array(symbol.dropFirst(2).utf8))
            if let path = try? parser.symbol() { return path }
        } else if symbol.hasPrefix("_ZN"), let legacy = legacy(symbol.dropFirst(3)) {
            return legacy
        }
        return name
    }

    /// The function's name without the generic arguments of its own path, which every instantiation shares:
    /// `crate::apply::<i32, …>` is `crate::apply`.
    static func function(_ name: String) -> String {
        let demangled = demangle(name)
        guard demangled.hasSuffix(">") else { return demangled }
        var depth = 0
        for index in demangled.indices.reversed() {
            switch demangled[index] {
            case ">": depth += 1
            case "<":
                depth -= 1
                if depth == 0 {
                    let prefix = demangled[..<index]
                    return prefix.hasSuffix("::") ? String(prefix.dropLast(2)) : demangled
                }
            default: break
            }
        }
        return demangled
    }

    private static func legacy(_ symbol: Substring) -> String? {
        var bytes = Array(symbol.utf8)
        var components: [String] = []
        while let first = bytes.first, first != UInt8(ascii: "E") {
            var length = 0
            while let digit = bytes.first, (48 ... 57).contains(digit) {
                length = length * 10 + Int(digit - 48)
                bytes.removeFirst()
                guard length <= 4096 else { return nil }
            }
            guard length > 0, bytes.count >= length, let part = String(bytes: bytes.prefix(length), encoding: .utf8)
            else { return nil }
            components.append(part)
            bytes.removeFirst(length)
        }
        guard bytes.first == UInt8(ascii: "E"), !components.isEmpty else { return nil }
        if let last = components.last, last.count == 17, last.hasPrefix("h"),
           last.dropFirst().allSatisfy(\.isHexDigit)
        {
            components.removeLast()
        }
        let escapes = [
            "$SP$": "@", "$BP$": "*", "$RF$": "&", "$LT$": "<", "$GT$": ">", "$LP$": "(", "$RP$": ")", "$C$": ",",
        ]
        return components.map { component in
            var part = component.hasPrefix("_$") ? String(component.dropFirst()) : component
            for (escape, value) in escapes {
                part = part.replacingOccurrences(of: escape, with: value)
            }
            while let range = part.range(of: #"\$u[0-9a-f]{2}\$"#, options: .regularExpression),
                  let scalar = UInt8(part[range].dropFirst(2).dropLast(), radix: 16)
            {
                part.replaceSubrange(range, with: String(UnicodeScalar(scalar)))
            }
            return part.replacingOccurrences(of: "..", with: "::")
        }.joined(separator: "::")
    }

    private struct Invalid: Error {}

    /// The v0 grammar (https://doc.rust-lang.org/rustc/symbol-mangling/v0.html), printing what `rustc-demangle`
    /// prints in its alternate form.
    private struct V0 {
        let bytes: [UInt8]
        var position = 0
        var depth = 0

        init(_ bytes: [UInt8]) { self.bytes = bytes }

        mutating func symbol() throws -> String {
            if let first = peek(), (48 ... 57).contains(first) { _ = try decimal() }
            let path = try path(inValue: true)
            // An instantiating crate may follow; a vendor suffix starts with `.`.
            if let next = peek(), next != UInt8(ascii: ".") { _ = try self.path(inValue: true) }
            return path
        }

        private func peek() -> UInt8? { position < bytes.count ? bytes[position] : nil }

        private mutating func next() throws -> UInt8 {
            guard position < bytes.count else { throw Invalid() }
            defer { position += 1 }
            return bytes[position]
        }

        private mutating func eat(_ character: Character) -> Bool {
            guard peek() == character.asciiValue else { return false }
            position += 1
            return true
        }

        private mutating func decimal() throws -> Int {
            var value = 0
            var digits = 0
            while let byte = peek(), (48 ... 57).contains(byte) {
                value = value * 10 + Int(byte - 48)
                position += 1
                digits += 1
                guard value <= 1_000_000 else { throw Invalid() }
            }
            guard digits > 0 else { throw Invalid() }
            return value
        }

        private mutating func base62() throws -> Int {
            if eat("_") { return 0 }
            var value = 0
            while true {
                let byte = try next()
                let digit: Int
                switch byte {
                case UInt8(ascii: "_"): return value &+ 1
                case 48 ... 57: digit = Int(byte - 48)
                case 97 ... 122: digit = 10 + Int(byte - 97)
                case 65 ... 90: digit = 36 + Int(byte - 65)
                default: throw Invalid()
                }
                // Crate disambiguators are 64-bit hashes; only back-references, which are small, need the value.
                value = value &* 62 &+ digit
            }
        }

        private mutating func disambiguator() throws -> Int {
            eat("s") ? try base62() &+ 1 : 0
        }

        private mutating func identifier() throws -> (name: String, disambiguator: Int) {
            let disambiguator = try disambiguator()
            let punycode = eat("u")
            let length = try decimal()
            _ = eat("_")
            guard position + length <= bytes.count,
                  let name = String(bytes: bytes[position ..< position + length], encoding: .utf8) else { throw Invalid() }
            position += length
            // Non-ASCII identifiers stay in their Punycode form.
            return (punycode ? "punycode{\(name)}" : name, disambiguator)
        }

        private mutating func backref<T>(_ body: (inout V0) throws -> T) throws -> T {
            let start = position - 1
            let target = try base62()
            guard target >= 0, target < start, depth < 200 else { throw Invalid() }
            var parser = V0(bytes)
            parser.position = target
            parser.depth = depth + 1
            return try body(&parser)
        }

        private mutating func nest<T>(_ body: (inout V0) throws -> T) throws -> T {
            depth += 1
            guard depth < 200 else { throw Invalid() }
            defer { depth -= 1 }
            return try body(&self)
        }

        mutating func path(inValue: Bool) throws -> String {
            try nest { parser in
                switch try parser.next() {
                case UInt8(ascii: "C"):
                    return try parser.identifier().name
                case UInt8(ascii: "M"):
                    _ = try parser.disambiguator()
                    _ = try parser.path(inValue: false)
                    return "<\(try parser.type())>"
                case UInt8(ascii: "X"):
                    _ = try parser.disambiguator()
                    _ = try parser.path(inValue: false)
                    let type = try parser.type()
                    return "<\(type) as \(try parser.path(inValue: false))>"
                case UInt8(ascii: "Y"):
                    let type = try parser.type()
                    return "<\(type) as \(try parser.path(inValue: false))>"
                case UInt8(ascii: "N"):
                    let namespace = try parser.next()
                    let path = try parser.path(inValue: inValue)
                    let identifier = try parser.identifier()
                    if (65 ... 90).contains(namespace) {
                        let kind = namespace == UInt8(ascii: "C") ? "closure" : namespace == UInt8(ascii: "S") ? "shim" :
                            String(UnicodeScalar(namespace))
                        let name = identifier.name.isEmpty ? "" : ":\(identifier.name)"
                        return "\(path)::{\(kind)\(name)#\(identifier.disambiguator)}"
                    }
                    return identifier.name.isEmpty ? path : "\(path)::\(identifier.name)"
                case UInt8(ascii: "I"):
                    let path = try parser.path(inValue: inValue)
                    var arguments: [String] = []
                    while !parser.eat("E") {
                        arguments.append(try parser.genericArgument())
                    }
                    let shown = arguments.filter { $0 != "'_" }
                    return shown.isEmpty ? path : "\(path)\(inValue ? "::" : "")<\(shown.joined(separator: ", "))>"
                case UInt8(ascii: "B"):
                    return try parser.backref { try $0.path(inValue: inValue) }
                default:
                    throw Invalid()
                }
            }
        }

        private mutating func genericArgument() throws -> String {
            if eat("L") {
                _ = try base62()
                return "'_"
            }
            if eat("K") { return try const() }
            return try type()
        }

        private static let basic: [UInt8: String] = [
            UInt8(ascii: "a"): "i8", UInt8(ascii: "b"): "bool", UInt8(ascii: "c"): "char", UInt8(ascii: "d"): "f64",
            UInt8(ascii: "e"): "str", UInt8(ascii: "f"): "f32", UInt8(ascii: "h"): "u8", UInt8(ascii: "i"): "isize",
            UInt8(ascii: "j"): "usize", UInt8(ascii: "l"): "i32", UInt8(ascii: "m"): "u32", UInt8(ascii: "n"): "i128",
            UInt8(ascii: "o"): "u128", UInt8(ascii: "s"): "i16", UInt8(ascii: "t"): "u16", UInt8(ascii: "u"): "()",
            UInt8(ascii: "v"): "...", UInt8(ascii: "x"): "i64", UInt8(ascii: "y"): "u64", UInt8(ascii: "z"): "!",
            UInt8(ascii: "p"): "_",
        ]

        private mutating func lifetime() throws -> String? {
            guard eat("L") else { return nil }
            _ = try base62()
            return "'_"
        }

        mutating func type() throws -> String {
            try nest { parser in
                guard let byte = parser.peek() else { throw Invalid() }
                if let basic = Self.basic[byte] {
                    parser.position += 1
                    return basic
                }
                switch byte {
                case UInt8(ascii: "A"):
                    parser.position += 1
                    let element = try parser.type()
                    return "[\(element); \(try parser.const())]"
                case UInt8(ascii: "S"):
                    parser.position += 1
                    return "[\(try parser.type())]"
                case UInt8(ascii: "T"):
                    parser.position += 1
                    var elements: [String] = []
                    while !parser.eat("E") {
                        elements.append(try parser.type())
                    }
                    return "(\(elements.joined(separator: ", "))\(elements.count == 1 ? "," : ""))"
                case UInt8(ascii: "R"), UInt8(ascii: "Q"):
                    parser.position += 1
                    _ = try parser.lifetime()
                    return (byte == UInt8(ascii: "R") ? "&" : "&mut ") + (try parser.type())
                case UInt8(ascii: "P"), UInt8(ascii: "O"):
                    parser.position += 1
                    return (byte == UInt8(ascii: "P") ? "*const " : "*mut ") + (try parser.type())
                case UInt8(ascii: "F"):
                    parser.position += 1
                    return try parser.function()
                case UInt8(ascii: "D"):
                    parser.position += 1
                    if parser.eat("G") { _ = try parser.base62() }
                    var traits: [String] = []
                    while !parser.eat("E") {
                        var trait = try parser.path(inValue: false)
                        var associated: [String] = []
                        while parser.eat("p") {
                            let name = try parser.identifier().name
                            associated.append("\(name) = \(try parser.type())")
                        }
                        if !associated.isEmpty {
                            trait = trait.hasSuffix(">") ? String(trait.dropLast()) + ", " + associated
                                .joined(separator: ", ") + ">"
                                : trait + "<" + associated.joined(separator: ", ") + ">"
                        }
                        traits.append(trait)
                    }
                    _ = try parser.lifetime()
                    return "dyn " + traits.joined(separator: " + ")
                case UInt8(ascii: "B"):
                    parser.position += 1
                    return try parser.backref { try $0.type() }
                default:
                    return try parser.path(inValue: false)
                }
            }
        }

        private mutating func function() throws -> String {
            if eat("G") { _ = try base62() }
            let unsafe = eat("U")
            var abi: String?
            if eat("K") {
                if eat("C") {
                    abi = "C"
                } else {
                    abi = try identifier().name.replacingOccurrences(of: "_", with: "-")
                }
            }
            var arguments: [String] = []
            while !eat("E") {
                arguments.append(try type())
            }
            let output = try type()
            return (unsafe ? "unsafe " : "") + (abi.map { "extern \"\($0)\" " } ?? "")
                + "fn(\(arguments.joined(separator: ", ")))" + (output == "()" ? "" : " -> \(output)")
        }

        private mutating func const() throws -> String {
            if eat("p") { return "_" }
            if eat("B") { return try backref { try $0.const() } }
            let type = try type()
            let negative = eat("n")
            var digits = ""
            while let byte = peek(), byte != UInt8(ascii: "_") {
                position += 1
                digits.append(Character(UnicodeScalar(byte)))
                guard digits.count <= 32 else { throw Invalid() }
            }
            guard eat("_") else { throw Invalid() }
            switch type {
            case "bool": return digits == "1" ? "true" : "false"
            case "char": return UInt32(digits, radix: 16).flatMap(UnicodeScalar.init).map { "'\(Character($0))'" } ?? "'?'"
            default:
                let value = digits.isEmpty ? "0" : UInt64(digits, radix: 16).map(String.init) ?? "0x\(digits)"
                return (negative ? "-" : "") + value
            }
        }
    }
}
