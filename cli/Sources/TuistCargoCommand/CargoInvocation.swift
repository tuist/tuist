import Foundation

struct CargoInvocation: Equatable {
    let arguments: [String]
    let commandIndex: Int?

    init(_ arguments: [String]) {
        self.arguments = arguments
        var index = 0
        while index < arguments.count {
            let value = arguments[index]
            if ["--config", "--color", "--manifest-path", "-C"].contains(value) {
                index += 2
            } else if value.hasPrefix("-") || value.hasPrefix("+") {
                index += 1
            } else {
                break
            }
        }
        commandIndex = index < arguments.count ? index : nil
    }

    var command: String? { commandIndex.map { arguments[$0] } }
    var toolchain: String? {
        guard let first = arguments.first, first.hasPrefix("+") else { return nil }
        return String(first.dropFirst())
    }

    var cargoArguments: [String] { toolchain == nil ? arguments : Array(arguments.dropFirst()) }

    var isNextestRun: Bool {
        guard command == "nextest", let commandIndex else { return false }
        return arguments.dropFirst(commandIndex + 1).first == "run"
    }

    var changesDirectory: Bool {
        arguments.prefix(commandIndex ?? arguments.count).contains { $0 == "-C" || ($0.hasPrefix("-C") && $0.count > 2) }
    }

    var observesBuild: Bool {
        ["build", "b", "check", "c", "test", "t", "clippy", "bench", "run", "r", "nextest", "test-build"].contains(command ?? "")
            && !changesDirectory && !arguments.contains("--help") && !arguments.contains("-h")
    }

    var executesTests: Bool {
        ["test", "t"].contains(command ?? "") && !arguments.prefix(while: { $0 != "--" }).contains("--no-run")
    }

    var reportsBuild: Bool { observesBuild && command != "nextest" }

    static func filterset(modules: [String]) -> String {
        if modules.isEmpty { return "none()" }
        return modules.sorted().map { "binary_id(=\(filterLiteral($0)))" }.joined(separator: " or ")
    }

    static func restrictingToModules(_ modules: [String], arguments: [String]) -> [String] {
        var retained: [String] = []
        var expressions: [String] = []
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            if option == "--" { retained += arguments[index...]; break }
            if option == "-E" || option == "--filterset", index + 1 < arguments.count {
                expressions.append(arguments[index + 1]); index += 2; continue
            }
            if option.hasPrefix("--filterset=") {
                expressions.append(String(option.dropFirst(12)))
            } else if option.hasPrefix("-E"), option.count > 2 {
                expressions.append(String(option.dropFirst(2)))
            } else {
                retained.append(option)
            }
            index += 1
        }
        var selection = "(\(filterset(modules: modules)))"
        // Nextest ORs repeated -E options. A shard must intersect their union, not add another alternative.
        if !expressions.isEmpty { selection += " and (\(expressions.map { "(\($0))" }.joined(separator: " or ")))" }
        return inserting(["-E", selection], into: retained)
    }

    static func filterLiteral(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
    }

    static func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func inserting(_ options: [String], into arguments: [String]) -> [String] {
        var result = arguments
        result.insert(contentsOf: options, at: arguments.firstIndex(of: "--") ?? arguments.endIndex)
        return result
    }
}

struct CargoCompilation: Codable, Equatable {
    var name: String
    var source: String
    var kind: String
    var dependencies: [String]
    var startOffsetMs: Int
    var durationMs: Int
    enum CodingKeys: String, CodingKey {
        case name, source, kind, dependencies, status, diagnostics
        case startOffsetMs = "start_offset_ms"
        case durationMs = "duration_ms"
    }

    var status: String
    var diagnostics: [CargoDiagnostic]
}

struct CargoDiagnostic: Codable, Equatable {
    var severity: String
    var message: String
    var file: String?
    var line: Int?
}
