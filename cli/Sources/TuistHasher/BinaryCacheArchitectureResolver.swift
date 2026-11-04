import FileSystem
import Foundation
import Path
import TuistCore
import XcodeGraph

/// Resolves the architectures a target builds for an SDK from the settings Tuist reads: the project's and
/// target's settings and xcconfig files, then `XCODE_XCCONFIG_FILE`. It returns `nil` for anything it
/// cannot evaluate exactly, such as other build settings in an architecture value, `[arch=...]`
/// conditions or `VALID_ARCHS`.
public final class BinaryCacheArchitectureResolver {
    private struct Assignment {
        let key: String
        let sdkPattern: String?
        let tokens: [String]
    }

    private static let keys: Set<String> = ["ARCHS", "EXCLUDED_ARCHS", "VALID_ARCHS"]

    private let fileSystem: FileSysteming
    private let environmentXCConfig: AbsolutePath?
    private var xcconfigs: [AbsolutePath: [Assignment]?] = [:]

    public init(environmentXCConfig: AbsolutePath? = nil, fileSystem: FileSysteming = FileSystem()) {
        self.environmentXCConfig = environmentXCConfig
        self.fileSystem = fileSystem
    }

    /// Whether the project's or target's settings dictionaries assign architecture settings.
    public static func declaresArchitectures(_ target: GraphTarget) -> Bool {
        [target.project.settings, target.target.settings].compactMap { $0 }.contains { settings in
            dictionaries(of: settings).contains { $0.keys.contains { keys.contains(baseKey($0)) } }
        }
    }

    public func architectures(of target: GraphTarget, variant: BinaryCacheVariant) async throws -> Set<BinaryArchitecture>? {
        let names = Set(target.project.settings.configurations.keys.map(\.name))
            .union((target.target.settings?.configurations.keys).map { Set($0.map(\.name)) } ?? [])
        var resolved: Set<BinaryArchitecture>?
        for name in names.isEmpty ? [nil] : names.sorted().map(Optional.some) {
            var levels: [[Assignment]] = []
            for settings in [target.project.settings, target.target.settings].compactMap({ $0 }) {
                let configuration = settings.configurations.first { $0.key.name == name }?.value ?? nil
                if let xcconfig = configuration?.xcconfig {
                    guard let assignments = try await assignments(in: xcconfig) else { return nil }
                    levels.append(assignments)
                }
                guard let assignments = Self.assignments(in: settings, configuration: configuration) else { return nil }
                levels.append(assignments)
            }
            if let environmentXCConfig {
                guard let assignments = try await assignments(in: environmentXCConfig) else { return nil }
                levels.append(assignments)
            }
            guard let value = Self.evaluate(levels, variant: variant) else { return nil }
            if let resolved, resolved != value { return nil }
            resolved = value
        }
        return resolved
    }

    private static func evaluate(_ levels: [[Assignment]], variant: BinaryCacheVariant) -> Set<BinaryArchitecture>? {
        let standard = variant.architectures.map(\.rawValue).sorted()
        guard !levels.joined().contains(where: { $0.key == "VALID_ARCHS" }),
              let archs = value(of: "ARCHS", in: levels, sdk: variant.sdk, standard: standard, default: standard),
              let excluded = value(of: "EXCLUDED_ARCHS", in: levels, sdk: variant.sdk, standard: standard, default: [])
        else { return nil }
        let names = archs.filter { !excluded.contains($0) }
        let result = Set(names.compactMap(BinaryArchitecture.init(rawValue:)))
        guard !result.isEmpty, result.count == Set(names).count else { return nil }
        return result
    }

    private static func value(
        of key: String, in levels: [[Assignment]], sdk: String, standard: [String], default value: [String]
    ) -> [String]? {
        var inherited = value
        for level in levels {
            let assignments = level.filter { $0.key == key }
            guard !assignments.isEmpty else { continue }
            var unconditional: Assignment?
            var conditional: Assignment?
            var conditionalPattern: String?
            for assignment in assignments {
                if let pattern = assignment.sdkPattern {
                    guard let matches = matches(pattern, sdk: sdk) else { return nil }
                    guard matches else { continue }
                    if let conditionalPattern, conditionalPattern != pattern { return nil }
                    if conditional != nil, assignment.tokens.contains(where: { $0.contains("$") }) { return nil }
                    conditional = assignment
                    conditionalPattern = pattern
                } else {
                    if unconditional != nil, assignment.tokens.contains(where: { $0.contains("$") }) { return nil }
                    unconditional = assignment
                }
            }
            guard let assignment = conditional ?? unconditional else { continue }
            if conditional != nil, unconditional != nil, assignment.tokens.contains(where: isInherited) { return nil }
            var tokens: [String] = []
            for token in assignment.tokens {
                if isInherited(token) {
                    tokens.append(contentsOf: inherited)
                } else if ["$(ARCHS_STANDARD)", "${ARCHS_STANDARD}", "$(ARCHS_STANDARD_64_BIT)", "${ARCHS_STANDARD_64_BIT}"]
                    .contains(token)
                {
                    tokens.append(contentsOf: standard)
                } else if token.contains("$") || token.contains("\"") || token.contains("'") {
                    return nil
                } else {
                    tokens.append(token)
                }
            }
            inherited = tokens
        }
        return inherited
    }

    private static func isInherited(_ token: String) -> Bool {
        ["$(inherited)", "${inherited}", "$inherited"].contains(token)
    }

    /// Xcode matches `sdk=` against names such as `iphonesimulator26.0`, so only a literal prefix followed
    /// by `*` has a meaning independent of the SDK version.
    private static func matches(_ pattern: String, sdk: String) -> Bool? {
        guard pattern.hasSuffix("*") else { return nil }
        let prefix = pattern.dropLast()
        guard !prefix.contains(where: { "*?[]".contains($0) }) else { return nil }
        if prefix.contains(where: \.isNumber) { return nil }
        return sdk.hasPrefix(prefix)
    }

    private static func baseKey(_ key: String) -> String {
        String(key.prefix { $0 != "[" }).trimmingCharacters(in: .whitespaces)
    }

    private static func assignment(key rawKey: String, tokens: [String]) -> Assignment?? {
        let key = baseKey(rawKey)
        guard keys.contains(key) else { return .some(nil) }
        let conditions = rawKey.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
        guard !conditions.isEmpty else { return Assignment(key: key, sdkPattern: nil, tokens: tokens) }
        guard conditions.hasPrefix("[sdk="), conditions.hasSuffix("]"),
              conditions.filter({ $0 == "[" }).count == 1
        else { return nil }
        return Assignment(key: key, sdkPattern: String(conditions.dropFirst(5).dropLast()), tokens: tokens)
    }

    private static func dictionaries(of settings: Settings) -> [SettingsDictionary] {
        [settings.base, settings.baseDebug] + settings.configurations.values.compactMap { $0?.settings }
    }

    private static func assignments(in settings: Settings, configuration: Configuration?) -> [Assignment]? {
        var merged = settings.base.merging(settings.baseDebug) { _, new in new }
        merged.merge(configuration?.settings ?? [:]) { _, new in new }
        var result: [Assignment] = []
        for (key, value) in merged.sorted(by: { $0.key < $1.key }) {
            let tokens: [String] = switch value {
            case let .string(string): string.split(whereSeparator: \.isWhitespace).map(String.init)
            case let .array(array): array.flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
            }
            guard let assignment = assignment(key: key, tokens: tokens) else { return nil }
            if let assignment { result.append(assignment) }
        }
        return result
    }

    private func assignments(in path: AbsolutePath, visiting: Set<AbsolutePath> = []) async throws -> [Assignment]? {
        if let cached = xcconfigs[path] { return cached }
        guard !visiting.contains(path), try await fileSystem.exists(path) else { return nil }
        var result: [Assignment]? = []
        for rawLine in try await fileSystem.readTextFile(at: path).components(separatedBy: .newlines) {
            let line = rawLine.components(separatedBy: "//")[0].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#include") {
                let optional = line.hasPrefix("#include?")
                let argument = line.dropFirst(optional ? 9 : 8).trimmingCharacters(in: .whitespaces)
                guard argument.count > 2, argument.hasPrefix("\""), argument.hasSuffix("\""),
                      let included = try? AbsolutePath(
                          validating: String(argument.dropFirst().dropLast()),
                          relativeTo: path.parentDirectory
                      )
                else { result = nil; break }
                if optional, try await !fileSystem.exists(included) { continue }
                guard let assignments = try await assignments(in: included, visiting: visiting.union([path])) else {
                    result = nil
                    break
                }
                result?.append(contentsOf: assignments)
                continue
            }
            var depth = 0
            guard let separator = line.firstIndex(where: { character in
                if character == "[" { depth += 1 } else if character == "]" { depth -= 1 }
                return character == "=" && depth == 0
            }) else { continue }
            let tokens = line[line.index(after: separator)...].split(whereSeparator: \.isWhitespace).map(String.init)
            guard let assignment = Self.assignment(key: String(line[..<separator]), tokens: tokens) else {
                result = nil
                break
            }
            if let assignment { result?.append(assignment) }
        }
        xcconfigs[path] = .some(result)
        return result
    }
}

extension BinaryCacheVariant {
    fileprivate var sdk: String {
        switch self {
        case .iosDevice: "iphoneos"
        case .iosSimulator: "iphonesimulator"
        case .catalyst, .macos: "macosx"
        }
    }
}
