import FileSystem
import Foundation
import Path
import TuistConfigLoader
import TuistConstants
import TuistCore
import TuistEnvironment
import TuistLoader
import TuistSupport
import XcodeGraph

/// This mapper sets the right setting for downstream targets that depend on static xcframeworks linked by dynamic
/// xcframeworks.
/// See this PR for more context: https://github.com/tuist/tuist/pull/6757
public struct StaticXCFrameworkModuleMapGraphMapper: GraphMapping {
    private struct ConditionedXCFramework {
        let xcframework: GraphDependency.XCFramework
        let condition: PlatformCondition?
    }

    private let fileSystem: FileSysteming
    private let manifestFilesLocator: ManifestFilesLocating
    private let configLoader: ConfigLoading
    private let swiftPackageManagerScratchDirectoryLocator: SwiftPackageManagerScratchDirectoryLocator

    public init(
        fileSystem: FileSysteming = FileSystem(),
        manifestFilesLocator: ManifestFilesLocating = ManifestFilesLocator(),
        configLoader: ConfigLoading = ConfigLoader(),
        swiftPackageManagerScratchDirectoryLocator: SwiftPackageManagerScratchDirectoryLocator =
            SwiftPackageManagerScratchDirectoryLocator()
    ) {
        self.fileSystem = fileSystem
        self.manifestFilesLocator = manifestFilesLocator
        self.configLoader = configLoader
        self.swiftPackageManagerScratchDirectoryLocator = swiftPackageManagerScratchDirectoryLocator
    }

    public func map(
        graph: Graph,
        environment: MapperEnvironment
    ) async throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        let graphWithDirectStaticXCFrameworkLinkerSettings = try await mapDynamicTargetsLinkedToStaticXCFrameworks(graph: graph)
        let derivedDirectory = try await derivedDirectory(for: graphWithDirectStaticXCFrameworkLinkerSettings)
        var sideEffects: [SideEffectDescriptor] = []
        let graphTraverser = GraphTraverser(graph: graphWithDirectStaticXCFrameworkLinkerSettings)

        let graph = try await mapGraph(
            graph: graphWithDirectStaticXCFrameworkLinkerSettings
        ) { graphTarget in
            let target = graphTarget.target
            let project = graphTarget.project
            let targetDependency = GraphDependency.target(name: target.name, path: project.path)
            let staticObjcXCFrameworksLinkedByDynamicXCFrameworkDependencies = graphTraverser
                .staticObjcXCFrameworksLinkedByDynamicXCFrameworkDependencies(
                    path: project.path,
                    name: target.name
                )
                .sorted()
                .compactMap { dependency -> ConditionedXCFramework? in
                    guard case let .xcframework(xcframework) = dependency,
                          case let .condition(condition) = graphTraverser.combinedCondition(
                              to: dependency,
                              from: targetDependency
                          )
                    else { return nil }
                    return ConditionedXCFramework(xcframework: xcframework, condition: condition)
                }

            // Static Swift xcframeworks reached through a dynamic xcframework are not relinked
            // at the consumer level (their symbols are already absorbed into the dynamic
            // xcframework's binary). They still need module visibility for the compiler to
            // resolve `import` statements that the dynamic xcframework's swiftinterface references.
            let staticSwiftXCFrameworksLinkedByDynamicXCFrameworkDependencies = graphTraverser
                .staticXCFrameworksLinkedByDynamicXCFrameworkDependencies(
                    path: project.path,
                    name: target.name
                )
                .sorted()
                .compactMap { dependency -> ConditionedXCFramework? in
                    guard case let .xcframework(xcframework) = dependency,
                          case let .condition(condition) = graphTraverser.combinedCondition(
                              to: dependency,
                              from: targetDependency
                          )
                    else { return nil }
                    return ConditionedXCFramework(xcframework: xcframework, condition: condition)
                }

            guard !staticObjcXCFrameworksLinkedByDynamicXCFrameworkDependencies.isEmpty
                || !staticSwiftXCFrameworksLinkedByDynamicXCFrameworkDependencies.isEmpty
            else { return [:] }

            let staticObjcXCFrameworksWithLibrariesLinkedByDynamicXCFrameworkDependencies =
                staticObjcXCFrameworksLinkedByDynamicXCFrameworkDependencies
                    .map(\.xcframework)
                    .filter { $0.containsLibrary() }

            sideEffects += try await generateModuleMapAndUmbrellaHeader(
                for: staticObjcXCFrameworksWithLibrariesLinkedByDynamicXCFrameworkDependencies,
                derivedDirectory: derivedDirectory
            )

            let staticObjcXCFrameworksWithoutLibrariesLinkedByDynamicXCFrameworkDependencies =
                staticObjcXCFrameworksLinkedByDynamicXCFrameworkDependencies
                    .filter { !$0.xcframework.containsLibrary() }

            var settings = SettingsDictionary()
            let xcframeworksRequiringPerSDKSearchPaths =
                staticObjcXCFrameworksWithoutLibrariesLinkedByDynamicXCFrameworkDependencies
                    + staticSwiftXCFrameworksLinkedByDynamicXCFrameworkDependencies
            if !xcframeworksRequiringPerSDKSearchPaths.isEmpty {
                var pathsBySDKCondition: [String: [String]] = [:]

                for conditionedXCFramework in xcframeworksRequiringPerSDKSearchPaths {
                    let xcframework = conditionedXCFramework.xcframework
                    for library in xcframework.infoPlist.libraries {
                        let platform = library.platform.graphPlatform
                        guard target.supportedPlatforms.contains(platform) else { continue }
                        guard library.applies(to: conditionedXCFramework.condition) else { continue }

                        let path =
                            "\"$(SRCROOT)/\(xcframework.path.appending(component: library.identifier).relative(to: project.path).pathString)\""
                        let sdkCondition = library.sdkCondition
                        pathsBySDKCondition[sdkCondition, default: []].append(path)
                    }
                }

                for sdkCondition in pathsBySDKCondition.keys.sorted() {
                    settings["FRAMEWORK_SEARCH_PATHS[\(sdkCondition)]"] = .array(
                        ["$(inherited)"] + pathsBySDKCondition[sdkCondition]!
                    )
                }
            }

            if !staticObjcXCFrameworksWithLibrariesLinkedByDynamicXCFrameworkDependencies.isEmpty {
                settings["OTHER_SWIFT_FLAGS"] = .array(
                    staticObjcXCFrameworksWithLibrariesLinkedByDynamicXCFrameworkDependencies.flatMap { xcframework -> [String] in
                        [
                            "-Xcc",
                            moduleMapFlag(
                                for: xcframework,
                                derivedDirectory: derivedDirectory,
                                project: project
                            ),
                        ]
                    }
                )
                settings["OTHER_C_FLAGS"] = .array(
                    staticObjcXCFrameworksWithLibrariesLinkedByDynamicXCFrameworkDependencies.flatMap { xcframework -> [String] in
                        [
                            moduleMapFlag(
                                for: xcframework,
                                derivedDirectory: derivedDirectory,
                                project: project
                            ),
                        ]
                    }
                )
                settings["HEADER_SEARCH_PATHS"] = .array(
                    staticObjcXCFrameworksWithLibrariesLinkedByDynamicXCFrameworkDependencies.flatMap { xcframework -> [String] in
                        guard let moduleMap = xcframework.moduleMaps.first
                        else { return [] }
                        return [
                            "\"$(SRCROOT)/\(moduleMap.parentDirectory.relative(to: project.path).pathString)\"",
                        ]
                    }
                )
            }

            return settings
        }

        return (
            graph,
            sideEffects,
            environment
        )
    }

    private func mapDynamicTargetsLinkedToStaticXCFrameworks(graph: Graph) async throws -> Graph {
        var graph = graph

        for (projectPath, project) in graph.projects {
            var project = project

            for (targetName, target) in project.targets {
                guard target.product.isDynamic else { continue }
                let targetDependency = GraphDependency.target(name: targetName, path: projectPath)

                let directStaticXCFrameworks = graph.dependencies[targetDependency, default: []]
                    .compactMap { dependency -> ConditionedXCFramework? in
                        guard case let .xcframework(xcframework) = dependency,
                              xcframework.linking == .static
                        else {
                            return nil
                        }
                        return ConditionedXCFramework(
                            xcframework: xcframework,
                            condition: graph.dependencyConditions[(targetDependency, dependency)]
                        )
                    }

                guard !directStaticXCFrameworks.isEmpty else { continue }

                let targetSettings = target.settings ?? Settings(
                    base: [:],
                    configurations: [:],
                    defaultSettings: project.settings.defaultSettings
                )
                let linkerSettings = try await linkerSettings(
                    for: directStaticXCFrameworks,
                    target: target
                )
                guard !linkerSettings.isEmpty else { continue }

                var updatedTarget = target
                updatedTarget.settings = targetSettings.with(
                    base: targetSettings.base
                        .combine(with: linkerSettings)
                        .removeDuplicates()
                )
                project.targets[targetName] = updatedTarget
            }

            graph.projects[projectPath] = project
        }

        return graph
    }

    private func derivedDirectory(for graph: Graph) async throws -> AbsolutePath {
        if let packageManifest = try await manifestFilesLocator.locatePackageManifest(at: graph.path) {
            let config = try await configLoader.loadConfig(path: graph.path)
            let arguments = config.project.generatedProject?.installOptions.passthroughSwiftPackageManagerArguments ?? []
            let scratchDirectory = try swiftPackageManagerScratchDirectoryLocator.locate(
                packagePath: packageManifest.parentDirectory,
                arguments: arguments,
                environment: Environment.current.variables,
                workingDirectory: try await Environment.current.currentWorkingDirectory()
            )
            return scratchDirectory.appending(
                components: [
                    Constants.DerivedDirectory.dependenciesDerivedDirectory,
                    Constants.DerivedDirectory.dependenciesXCFrameworkDirectory,
                ]
            )
        } else {
            return graph.path.appending(
                components: [
                    Constants.tuistDirectoryName,
                    Constants.SwiftPackageManager.packageBuildDirectoryName,
                    Constants.DerivedDirectory.dependenciesDerivedDirectory,
                    Constants.DerivedDirectory.dependenciesXCFrameworkDirectory,
                ]
            )
        }
    }

    private func moduleMapFlag(
        for xcframework: GraphDependency.XCFramework,
        derivedDirectory: AbsolutePath,
        project: Project
    ) -> String {
        let name = xcframework.path.basenameWithoutExt
        return "-fmodule-map-file=\"$(SRCROOT)/\(derivedDirectory.appending(components: name, "Headers", "module.modulemap").relative(to: project.path).pathString)\""
    }

    /// Generates modulemap and an umbrella header that can be referenced from downstream targets.
    private func generateModuleMapAndUmbrellaHeader(
        for staticObjcXCFrameworksLinkedByDynamicXCFrameworkDependencies: [GraphDependency.XCFramework],
        derivedDirectory: AbsolutePath
    ) async throws -> [SideEffectDescriptor] {
        let fileSystem = fileSystem
        return try await staticObjcXCFrameworksLinkedByDynamicXCFrameworkDependencies
            .concurrentFlatMap { xcframework -> [SideEffectDescriptor] in
                guard let moduleMap = xcframework.moduleMaps.first
                else { return [] }
                let name = xcframework.path.basenameWithoutExt
                let umbrellaHeader = try await fileSystem.glob(directory: xcframework.path, include: ["**/\(name).h"]).collect()
                    .first
                let headersDirectory = derivedDirectory.appending(components: name, "Headers")
                var sideEffects: [SideEffectDescriptor] = [
                    .directory(DirectoryDescriptor(path: headersDirectory)),
                    .file(
                        FileDescriptor(
                            path: headersDirectory.appending(components: "module.modulemap"),
                            contents: try await fileSystem.readFile(at: moduleMap)
                        )
                    ),
                ]

                if let umbrellaHeader {
                    sideEffects.append(
                        .file(
                            FileDescriptor(
                                path: headersDirectory.appending(components: "\(name).h"),
                                contents: String(data: try await fileSystem.readFile(at: umbrellaHeader), encoding: .utf8)?
                                    .replacingOccurrences(of: "<\(name)/", with: "<")
                                    .data(using: .utf8)
                            )
                        )
                    )
                }

                return sideEffects
            }
    }

    private func linkerSettings(
        for xcframeworks: [ConditionedXCFramework],
        target: Target
    ) async throws -> SettingsDictionary {
        var settings = SettingsDictionary()

        for conditionedXCFramework in xcframeworks.sorted(by: { $0.xcframework < $1.xcframework }) {
            let xcframework = conditionedXCFramework.xcframework
            for library in xcframework.infoPlist.libraries {
                let platform = library.platform.graphPlatform
                guard target.supportedPlatforms.contains(platform) else { continue }
                guard library.applies(to: conditionedXCFramework.condition) else { continue }
                let moduleMapLinkerFlags = try await moduleMapLinkerFlags(
                    for: library,
                    in: xcframework
                )

                let key = "OTHER_LDFLAGS[\(library.sdkCondition)]"
                let existingFlags: [String]
                switch settings[key] {
                case let .array(value):
                    existingFlags = value
                case let .string(value):
                    existingFlags = [value]
                case .none:
                    existingFlags = ["$(inherited)"]
                }
                let newFlags = existingFlags
                    + [forceLoadFlag(for: library)]
                    + moduleMapLinkerFlags
                settings[key] = .array(newFlags)
            }
        }

        return settings
    }

    private func moduleMapLinkerFlags(
        for library: XCFrameworkInfoPlist.Library,
        in xcframework: GraphDependency.XCFramework
    ) async throws -> [String] {
        var flags: [String] = []
        let sliceDirectory = xcframework.path.appending(component: library.identifier)
        let moduleMaps = xcframework.moduleMaps
            .filter { $0.isDescendantOfOrEqual(to: sliceDirectory) }
        let moduleMapsToParse = moduleMaps.isEmpty ? xcframework.moduleMaps : moduleMaps

        for moduleMap in moduleMapsToParse.sorted() {
            let contents = try await fileSystem.readTextFile(at: moduleMap)
            var parser = ModuleMapLinkerFlagsParser(contents: contents)
            flags.append(contentsOf: parser.parse())
        }

        return flags
    }

    private func forceLoadFlag(for library: XCFrameworkInfoPlist.Library) -> String {
        "-Wl,-force_load,$(TARGET_BUILD_DIR)/\(library.forceLoadPath)"
    }

    private func mapGraph(
        graph: Graph,
        targetSettings: (GraphTarget) async throws -> SettingsDictionary
    ) async throws -> Graph {
        var graph = graph
        var settings: [GraphDependency: SettingsDictionary] = [:]
        let targets = try GraphTraverser(graph: graph).allTargetsTopologicalSorted()
        for target in targets {
            guard let dependencies = graph.dependencies[.target(name: target.target.name, path: target.path)] else { continue }
            let targetDependency: GraphDependency = .target(name: target.target.name, path: target.path)
            settings[targetDependency] = try await targetSettings(target)
            for dependency in dependencies.sorted() {
                var dependencySettings = settings[dependency] ?? [:]

                if case let GraphDependency.target(_, dependencyPath, _) = dependency,
                   dependencyPath != target.path
                {
                    dependencySettings = dependencySettings.resolvingSrcRootPaths(
                        from: dependencyPath,
                        to: target.path
                    )
                }

                settings[targetDependency] = (settings[targetDependency] ?? [:])
                    .combine(with: dependencySettings)
                    .removeDuplicates()
            }
        }
        graph.projects = graph.projects.mapValues { project in
            var project = project
            project.targets = project.targets.mapValues { target in
                var target = target
                let targetSettings = target.settings ?? Settings(
                    base: [:],
                    configurations: [:],
                    defaultSettings: project.settings.defaultSettings
                )
                target.settings = targetSettings.with(
                    base: targetSettings.base
                        .combine(with: settings[.target(name: target.name, path: project.path)] ?? SettingsDictionary())
                        .removeDuplicates()
                )
                return target
            }
            return project
        }
        return graph
    }
}

private struct ModuleMapLinkerFlagsParser {
    private enum Token: Equatable {
        case identifier(String)
        case stringLiteral(String)
        case leftBrace
        case rightBrace
        case eof
    }

    private let tokens: [Token]
    private var currentIndex = 0

    init(contents: String) {
        tokens = Self.tokenize(contents: contents)
    }

    mutating func parse() -> [String] {
        while !isAtEnd {
            if startsModuleDeclaration {
                consumeModuleDeclaration()
                guard consumeLeftBrace() else { continue }
                return parseModuleBody(linkAllowed: true)
            }
            advance()
        }
        return []
    }

    private mutating func parseModuleBody(linkAllowed: Bool) -> [String] {
        var flags: [String] = []

        while !isAtEnd {
            if consumeRightBrace() {
                return flags
            } else if startsModuleDeclaration {
                consumeModuleDeclaration()
                if consumeLeftBrace() {
                    _ = parseModuleBody(linkAllowed: false)
                }
            } else if linkAllowed, consumeIdentifier("link") {
                let isFramework = consumeIdentifier("framework")
                guard case let .stringLiteral(name) = advance() else { continue }
                flags.append(contentsOf: isFramework ? ["-framework", name] : ["-l\(name)"])
            } else if consumeLeftBrace() {
                skipBalancedBlock()
            } else {
                advance()
            }
        }

        return flags
    }

    private var startsModuleDeclaration: Bool {
        var index = currentIndex
        while case let .identifier(identifier) = tokens[index],
              ["explicit", "framework", "extern"].contains(identifier)
        {
            index += 1
        }

        if case let .identifier(identifier) = tokens[index] {
            return identifier == "module"
        }
        return false
    }

    private mutating func consumeModuleDeclaration() {
        while !isAtEnd {
            if case .leftBrace = peek() { return }
            advance()
        }
    }

    private mutating func skipBalancedBlock() {
        var depth = 1
        while !isAtEnd, depth > 0 {
            switch advance() {
            case .leftBrace:
                depth += 1
            case .rightBrace:
                depth -= 1
            case .identifier, .stringLiteral, .eof:
                break
            }
        }
    }

    private var isAtEnd: Bool {
        peek() == .eof
    }

    private func peek() -> Token {
        tokens[currentIndex]
    }

    @discardableResult
    private mutating func advance() -> Token {
        let token = tokens[currentIndex]
        if token != .eof {
            currentIndex += 1
        }
        return token
    }

    private mutating func consumeIdentifier(_ expected: String) -> Bool {
        guard case let .identifier(identifier) = peek(), identifier == expected else { return false }
        advance()
        return true
    }

    private mutating func consumeLeftBrace() -> Bool {
        guard case .leftBrace = peek() else { return false }
        advance()
        return true
    }

    private mutating func consumeRightBrace() -> Bool {
        guard case .rightBrace = peek() else { return false }
        advance()
        return true
    }

    private static func tokenize(contents: String) -> [Token] {
        var tokens: [Token] = []
        var currentIndex = contents.startIndex

        while currentIndex < contents.endIndex {
            let character = contents[currentIndex]

            if character.isWhitespace {
                contents.formIndex(after: &currentIndex)
            } else if character == "/" {
                let nextIndex = contents.index(after: currentIndex)
                guard nextIndex < contents.endIndex else {
                    contents.formIndex(after: &currentIndex)
                    continue
                }

                switch contents[nextIndex] {
                case "/":
                    currentIndex = contents.index(after: nextIndex)
                    while currentIndex < contents.endIndex, !contents[currentIndex].isNewline {
                        contents.formIndex(after: &currentIndex)
                    }
                case "*":
                    currentIndex = contents.index(after: nextIndex)
                    while currentIndex < contents.endIndex {
                        let nextIndex = contents.index(after: currentIndex)
                        guard nextIndex < contents.endIndex else {
                            currentIndex = contents.endIndex
                            break
                        }

                        if contents[currentIndex] == "*", contents[nextIndex] == "/" {
                            currentIndex = contents.index(after: nextIndex)
                            break
                        }
                        contents.formIndex(after: &currentIndex)
                    }
                default:
                    tokens.append(.identifier(String(character)))
                    contents.formIndex(after: &currentIndex)
                }
            } else if character == "{" {
                tokens.append(.leftBrace)
                contents.formIndex(after: &currentIndex)
            } else if character == "}" {
                tokens.append(.rightBrace)
                contents.formIndex(after: &currentIndex)
            } else if character == "\"" {
                contents.formIndex(after: &currentIndex)
                var value = ""

                while currentIndex < contents.endIndex {
                    let character = contents[currentIndex]
                    contents.formIndex(after: &currentIndex)

                    if character == "\\" {
                        guard currentIndex < contents.endIndex else { break }
                        value.append(contents[currentIndex])
                        contents.formIndex(after: &currentIndex)
                    } else if character == "\"" {
                        break
                    } else {
                        value.append(character)
                    }
                }

                tokens.append(.stringLiteral(value))
            } else {
                var value = ""
                while currentIndex < contents.endIndex {
                    let character = contents[currentIndex]
                    guard !character.isWhitespace, !["{", "}", "\"", "/"].contains(character) else { break }
                    value.append(character)
                    contents.formIndex(after: &currentIndex)
                }

                if value.isEmpty {
                    contents.formIndex(after: &currentIndex)
                } else {
                    tokens.append(.identifier(value))
                }
            }
        }

        tokens.append(.eof)
        return tokens
    }
}

extension SettingsDictionary {
    func resolvingSrcRootPaths(
        from sourcePath: AbsolutePath,
        to destinationPath: AbsolutePath
    ) -> SettingsDictionary {
        mapValues { value in
            switch value {
            case let .string(stringValue):
                return .string(stringValue.resolvingSrcRootPath(from: sourcePath, to: destinationPath))
            case let .array(arrayValue):
                return .array(arrayValue.map { $0.resolvingSrcRootPath(from: sourcePath, to: destinationPath) })
            }
        }
    }

    /// Combining target settings can introduce duplicates when a graph reaches the same dependency through multiple paths.
    /// This is also why the `removeOtherSwiftFlagsDuplicates` is `internal` instead of `fileprivate`, so we can test the
    /// method itself in isolation.
    fileprivate func removeDuplicates() -> SettingsDictionary {
        removeDuplicates(for: "FRAMEWORK_SEARCH_PATHS")
            .removeDuplicates(for: "HEADER_SEARCH_PATHS")
            .removeDuplicates(for: "OTHER_C_FLAGS")
            .removeDuplicates(forConditionedKey: "FRAMEWORK_SEARCH_PATHS")
            .removeDuplicates(forConditionedKey: "HEADER_SEARCH_PATHS")
            .removeDuplicates(forConditionedKey: "OTHER_C_FLAGS")
            .removeOtherLdFlagsDuplicates()
            .removeOtherSwiftFlagsDuplicates()
    }

    func removeOtherLdFlagsDuplicates() -> SettingsDictionary {
        var settings = self
        let keys = settings.keys.filter { $0 == "OTHER_LDFLAGS" || $0.hasPrefix("OTHER_LDFLAGS[") }
        for key in keys {
            guard let value = settings[key] else { continue }
            switch value {
            case let .string(value):
                settings[key] = .string(value)
            case let .array(value):
                var seen = Set<String>()
                let value = value.enumerated().filter {
                    if $0.element.isLdFlagWithArgument {
                        if value.endIndex > $0.offset + 1 {
                            return !seen.contains($0.element + value[$0.offset + 1])
                        } else {
                            return true
                        }
                    } else {
                        if $0.offset == 0 {
                            return seen.insert($0.element).inserted
                        } else {
                            let previousElement = value[$0.offset - 1]
                            if previousElement.isLdFlagWithArgument {
                                return seen.insert(previousElement + $0.element).inserted
                            } else {
                                return seen.insert($0.element).inserted
                            }
                        }
                    }
                }
                settings[key] = .array(
                    value.map(\.element)
                )
            }
        }
        return settings
    }

    func removeOtherSwiftFlagsDuplicates() -> SettingsDictionary {
        var settings = self
        let keys = settings.keys.filter { $0 == "OTHER_SWIFT_FLAGS" || $0.hasPrefix("OTHER_SWIFT_FLAGS[") }
        for key in keys {
            guard let value = settings[key] else { continue }
            switch value {
            case let .string(value):
                settings[key] = .string(value)
            case let .array(value):
                var seen = Set<String>()
                let value = value.enumerated().filter {
                    if $0.element.isFlagWithArgument {
                        if value.endIndex > $0.offset + 1 {
                            return !seen.contains($0.element + value[$0.offset + 1])
                        } else {
                            return true
                        }
                    } else {
                        if $0.offset == 0 {
                            return seen.insert($0.element).inserted
                        } else {
                            let previousElement = value[$0.offset - 1]
                            if previousElement.isFlagWithArgument {
                                return seen.insert(previousElement + $0.element).inserted
                            } else {
                                return seen.insert($0.element).inserted
                            }
                        }
                    }
                }
                settings[key] = .array(
                    value.map(\.element)
                )
            }
        }
        return settings
    }

    fileprivate func removeDuplicates(for key: String) -> SettingsDictionary {
        var settings = self
        guard let value = settings[key] else { return settings }
        switch value {
        case let .string(value):
            settings[key] = .string(value)
        case let .array(value):
            settings[key] = .array(
                value.uniqued()
            )
        }
        return settings
    }

    fileprivate func removeDuplicates(forConditionedKey key: String) -> SettingsDictionary {
        var settings = self
        let conditionedKeys = settings.keys.filter { $0.hasPrefix("\(key)[") }
        for conditionedKey in conditionedKeys {
            guard let value = settings[conditionedKey] else { continue }
            switch value {
            case let .string(value):
                settings[conditionedKey] = .string(value)
            case let .array(value):
                settings[conditionedKey] = .array(value.uniquedPreservingOrder())
            }
        }
        return settings
    }
}

extension [String] {
    fileprivate func uniquedPreservingOrder() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}

extension XCFrameworkInfoPlist.Library.Platform {
    fileprivate var graphPlatform: XcodeGraph.Platform {
        switch self {
        case .iOS: return .iOS
        case .macOS: return .macOS
        case .tvOS: return .tvOS
        case .watchOS: return .watchOS
        case .visionOS: return .visionOS
        }
    }
}

extension XCFrameworkInfoPlist.Library {
    fileprivate var sdkCondition: String {
        let graphPlatform = platform.graphPlatform
        switch platformVariant {
        case .simulator:
            if let simulatorSDK = graphPlatform.xcodeSimulatorSDK {
                return "sdk=\(simulatorSDK)*"
            }
            return "sdk=\(graphPlatform.xcodeSdkRoot)*"
        case .maccatalyst:
            return "sdk=macosx*"
        case nil:
            return "sdk=\(graphPlatform.xcodeSdkRoot)*"
        }
    }

    fileprivate func applies(to condition: PlatformCondition?) -> Bool {
        guard let condition else { return true }
        return condition.platformFilters.contains(platformFilter)
    }

    private var platformFilter: PlatformFilter {
        switch platformVariant {
        case .maccatalyst:
            return .catalyst
        case .simulator, nil:
            switch platform {
            case .iOS: return .ios
            case .macOS: return .macos
            case .tvOS: return .tvos
            case .watchOS: return .watchos
            case .visionOS: return .visionos
            }
        }
    }
}

extension GraphDependency.XCFramework {
    fileprivate func containsLibrary() -> Bool {
        infoPlist.libraries
            .contains(where: { $0.path.extension == "a" })
    }
}

extension String {
    fileprivate var isLdFlagWithArgument: Bool {
        [
            "-Xlinker",
            "-framework",
            "-weak_framework",
            "-reexport_framework",
            "-lazy_framework",
            "-force_load",
            "-weak_library",
            "-reexport_library",
            "-lazy_library",
        ].contains(self)
    }

    fileprivate var isFlagWithArgument: Bool {
        starts(with: "-X") ||
            self == "-I" ||
            self == "-enable-upcoming-feature" ||
            self == "-enable-experimental-feature"
    }

    fileprivate func resolvingSrcRootPath(
        from sourcePath: AbsolutePath,
        to destinationPath: AbsolutePath
    ) -> String {
        let srcRootMarker = "$(SRCROOT)"
        guard contains(srcRootMarker) else { return self }

        var pathComponents = split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let srcRootIndex = pathComponents.firstIndex(where: { $0.contains(srcRootMarker) }) else { return self }

        let prefix = String(pathComponents[srcRootIndex].prefix(while: { $0 != "$" }))
        let suffix = pathComponents.last?.hasSuffix("\"") == true ? "\"" : ""

        pathComponents[srcRootIndex] = srcRootMarker

        let relativePathString = pathComponents[(srcRootIndex + 1)...]
            .joined(separator: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

        guard let relativePath = try? RelativePath(validating: relativePathString) else { return self }

        let absolutePath = sourcePath.appending(relativePath)
        let resolvedComponents = absolutePath.relative(to: destinationPath).components

        return prefix + (pathComponents[...srcRootIndex] + resolvedComponents).joined(separator: "/") + suffix
    }
}

extension XCFrameworkInfoPlist.Library {
    fileprivate var forceLoadPath: String {
        if path.extension == "framework" {
            return "\(path.pathString)/\(binaryName)"
        }
        return path.pathString
    }
}
