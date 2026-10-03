import FileSystem
import Foundation
import Path
import TuistConstants
import TuistCore
import TuistSupport
import XcodeGraph

struct PreselectedXCFrameworkSlicesGraphMapper: GraphMapping {
    private static let derivedDirectoryName = "PreselectedXCFrameworkSlices"
    private static let frameworkSearchPathsSetting = "FRAMEWORK_SEARCH_PATHS"
    private static let otherCFlagsSetting = "OTHER_CFLAGS"
    private static let otherSwiftFlagsSetting = "OTHER_SWIFT_FLAGS"
    private static let otherLinkerFlagsSetting = "OTHER_LDFLAGS"

    private let fileSystem: FileSysteming

    init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    private struct TargetID: Hashable {
        let projectPath: AbsolutePath
        let targetName: String
    }

    private struct SDKVariant: Hashable, Comparable {
        let sdk: String
        let platform: XCFrameworkInfoPlist.Library.Platform
        let platformVariant: XCFrameworkInfoPlist.Library.PlatformVariant?

        static func < (lhs: SDKVariant, rhs: SDKVariant) -> Bool {
            lhs.sdk < rhs.sdk
        }
    }

    private struct SelectedFramework: Hashable {
        let xcframeworkPath: AbsolutePath
        let frameworkPath: AbsolutePath
        let frameworkName: String
        let linking: BinaryLinking
    }

    private struct FrameworkUse {
        let framework: SelectedFramework
        var linkStatus: LinkingStatus?
        var runtime: Bool

        mutating func merge(usage: Usage, status: LinkingStatus) {
            switch usage {
            case .searchable:
                break
            case .linkable:
                linkStatus = Self.stronger(lhs: linkStatus, rhs: status)
            case .runtime:
                runtime = runtime || framework.linking == .dynamic
            }
        }

        private static func stronger(lhs: LinkingStatus?, rhs: LinkingStatus) -> LinkingStatus {
            if lhs == .required || rhs == .required { return .required }
            if lhs == .optional || rhs == .optional { return .optional }
            return .none
        }
    }

    private struct SDKPlan {
        var frameworksByName: [String: FrameworkUse] = [:]

        var isEmpty: Bool {
            frameworksByName.isEmpty
        }
    }

    private struct TargetPlan {
        let project: Project
        let target: Target
        var sdkPlans: [SDKVariant: SDKPlan] = [:]

        var isEmpty: Bool {
            sdkPlans.isEmpty
        }

        func removingFrameworks(from fallbackXCFrameworkPaths: Set<AbsolutePath>) -> Self {
            var plan = self
            plan.sdkPlans = Dictionary(uniqueKeysWithValues: sdkPlans.compactMap { variant, sdkPlan in
                var sdkPlan = sdkPlan
                sdkPlan.frameworksByName = sdkPlan.frameworksByName.filter { _, frameworkUse in
                    !fallbackXCFrameworkPaths.contains(frameworkUse.framework.xcframeworkPath)
                }
                return sdkPlan.isEmpty ? nil : (variant, sdkPlan)
            })
            return plan
        }
    }

    private enum Usage {
        case searchable
        case linkable
        case runtime
    }

    func map(
        graph: Graph,
        environment: MapperEnvironment
    ) async throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        let graphTraverser = GraphTraverser(graph: graph)
        let linkingByXCFrameworkPath = graph.linkingByXCFrameworkPath
        var plans: [TargetID: TargetPlan] = [:]
        var fallbackXCFrameworkPaths = Set<AbsolutePath>()

        for (_, project) in graph.projects {
            for (_, target) in project.targets {
                let targetID = TargetID(projectPath: project.path, targetName: target.name)
                var targetPlan = TargetPlan(project: project, target: target)

                let searchableDependencies = try graphTraverser.searchablePathDependencies(
                    path: project.path,
                    name: target.name
                )
                for dependency in searchableDependencies {
                    try await collect(
                        dependency: dependency,
                        usage: .searchable,
                        target: target,
                        project: project,
                        linkingByXCFrameworkPath: linkingByXCFrameworkPath,
                        targetPlan: &targetPlan,
                        fallbackXCFrameworkPaths: &fallbackXCFrameworkPaths
                    )
                }

                let linkableDependencies = try graphTraverser.linkableDependencies(
                    path: project.path,
                    name: target.name
                )
                for dependency in linkableDependencies {
                    if target.product == .commandLineTool {
                        try await collect(
                            dependency: dependency,
                            usage: .runtime,
                            target: target,
                            project: project,
                            linkingByXCFrameworkPath: linkingByXCFrameworkPath,
                            targetPlan: &targetPlan,
                            fallbackXCFrameworkPaths: &fallbackXCFrameworkPaths
                        )
                    }
                    try await collect(
                        dependency: dependency,
                        usage: .linkable,
                        target: target,
                        project: project,
                        linkingByXCFrameworkPath: linkingByXCFrameworkPath,
                        targetPlan: &targetPlan,
                        fallbackXCFrameworkPaths: &fallbackXCFrameworkPaths
                    )
                }

                let runtimeDependencies = graphTraverser.embeddableFrameworks(path: project.path, name: target.name)
                for dependency in runtimeDependencies {
                    try await collect(
                        dependency: dependency,
                        usage: .runtime,
                        target: target,
                        project: project,
                        linkingByXCFrameworkPath: linkingByXCFrameworkPath,
                        targetPlan: &targetPlan,
                        fallbackXCFrameworkPaths: &fallbackXCFrameworkPaths
                    )
                }

                if !targetPlan.isEmpty {
                    plans[targetID] = targetPlan
                }
            }
        }

        plans = plans.compactMapValues { plan in
            let filtered = plan.removingFrameworks(from: fallbackXCFrameworkPaths)
            return filtered.isEmpty ? nil : filtered
        }

        let selectedXCFrameworkPaths = Set(
            plans.values.flatMap { plan in
                plan.sdkPlans.values.flatMap { sdkPlan in
                    sdkPlan.frameworksByName.values.map(\.framework.xcframeworkPath)
                }
            }
        )
        guard !selectedXCFrameworkPaths.isEmpty else {
            return (graph, [], environment)
        }

        var sideEffects: [SideEffectDescriptor] = []
        var activeFilesByDirectory: [AbsolutePath: Set<AbsolutePath>] = [:]
        var generatedDirectories = Set<AbsolutePath>()
        var targetSettings: [TargetID: [(key: String, values: [String])]] = [:]
        var targetRuntimeScripts: [TargetID: TargetScript] = [:]

        for (targetID, plan) in plans {
            let derivedDirectory = Self.derivedDirectory(sourceRootPath: plan.project.sourceRootPath)
            generatedDirectories.insert(derivedDirectory)

            var additions: [(key: String, values: [String])] = []

            for (variant, sdkPlan) in plan.sdkPlans.sorted(by: { $0.key < $1.key }) {
                let frameworkDirectory = Self.frameworkDirectory(
                    sourceRootPath: plan.project.sourceRootPath,
                    targetName: plan.target.name,
                    sdk: variant.sdk
                )
                let frameworkDirectoryValue = "$(SRCROOT)/\(frameworkDirectory.relative(to: plan.project.sourceRootPath).pathString)"

                for frameworkUse in sdkPlan.frameworksByName.values {
                    let linkPath = frameworkDirectory.appending(component: "\(frameworkUse.framework.frameworkName).framework")
                    activeFilesByDirectory[derivedDirectory, default: []].insert(linkPath)
                    sideEffects.append(
                        .symbolicLink(
                            SymbolicLinkDescriptor(
                                path: linkPath,
                                destination: frameworkUse.framework.frameworkPath
                            )
                        )
                    )
                }

                let sdkQualifier = "[sdk=\(variant.sdk)*]"
                additions.append((
                    "\(Self.frameworkSearchPathsSetting)\(sdkQualifier)",
                    [frameworkDirectoryValue]
                ))
                additions.append((
                    "\(Self.otherCFlagsSetting)\(sdkQualifier)",
                    ["-F", frameworkDirectoryValue]
                ))
                additions.append((
                    "\(Self.otherSwiftFlagsSetting)\(sdkQualifier)",
                    ["-F", frameworkDirectoryValue]
                ))

                let linkedFrameworks = sdkPlan.frameworksByName.values
                    .compactMap { frameworkUse -> (name: String, status: LinkingStatus)? in
                        guard let linkStatus = frameworkUse.linkStatus, linkStatus != .none else { return nil }
                        return (frameworkUse.framework.frameworkName, linkStatus)
                    }
                    .sorted { lhs, rhs in lhs.name < rhs.name }

                if !linkedFrameworks.isEmpty {
                    let responseFilePath = frameworkDirectory.appending(component: "\(plan.target.name)-\(variant.sdk).resp")
                    let responseFileContents = (
                        ["-F\(frameworkDirectory.pathString)"] +
                            linkedFrameworks.flatMap { framework -> [String] in
                                switch framework.status {
                                case .required:
                                    return ["-framework", framework.name]
                                case .optional:
                                    return ["-weak_framework", framework.name]
                                case .none:
                                    return []
                                }
                            }
                    )
                    .joined(separator: "\n")
                        + "\n"
                    activeFilesByDirectory[derivedDirectory, default: []].insert(responseFilePath)
                    sideEffects.append(
                        .file(FileDescriptor(path: responseFilePath, contents: Data(responseFileContents.utf8)))
                    )
                    additions.append((
                        "\(Self.otherLinkerFlagsSetting)\(sdkQualifier)",
                        ["\"@$(SRCROOT)/\(responseFilePath.relative(to: plan.project.sourceRootPath).pathString)\""]
                    ))
                }
            }

            targetSettings[targetID] = additions

            if let script = runtimeScript(plan: plan) {
                targetRuntimeScripts[targetID] = script
            }
        }

        if !generatedDirectories.isEmpty {
            sideEffects.insert(
                .generatedFilesCleanup(
                    GeneratedFilesCleanupDescriptor(
                        directories: generatedDirectories,
                        activeFilesByDirectory: activeFilesByDirectory,
                        include: ["**/*.framework", "**/*.resp"]
                    )
                ),
                at: 0
            )
        }

        var graph = graph.removingXCFrameworkDependencies(at: selectedXCFrameworkPaths)
        graph.projects = Dictionary(uniqueKeysWithValues: graph.projects.map { projectPath, project in
            var project = project
            project.targets = Dictionary(uniqueKeysWithValues: project.targets.map { targetName, target in
                let targetID = TargetID(projectPath: projectPath, targetName: targetName)
                var target = target
                if let additions = targetSettings[targetID] {
                    target.settings = Self.apply(
                        additions,
                        to: target.settings,
                        defaultSettings: project.settings.defaultSettings
                    )
                }
                if let script = targetRuntimeScripts[targetID] {
                    target.scripts.append(script)
                }
                return (targetName, target)
            })
            return (projectPath, project)
        })

        return (graph, sideEffects, environment)
    }

    private func collect(
        dependency: GraphDependencyReference,
        usage: Usage,
        target: Target,
        project: Project,
        linkingByXCFrameworkPath: [AbsolutePath: BinaryLinking],
        targetPlan: inout TargetPlan,
        fallbackXCFrameworkPaths: inout Set<AbsolutePath>
    ) async throws {
        guard case let .xcframework(path, _, infoPlist, status, condition) = dependency else { return }
        guard status != .none else { return }
        guard let linking = linkingByXCFrameworkPath[path] else {
            fallbackXCFrameworkPaths.insert(path)
            return
        }

        let platformFilters = condition?.platformFilters ?? target.dependencyPlatformFilters
        guard let variants = Self.variants(platformFilters: platformFilters), !variants.isEmpty else {
            fallbackXCFrameworkPaths.insert(path)
            return
        }

        for variant in variants {
            guard let selectedFramework = try await selectedFramework(
                xcframeworkPath: path,
                infoPlist: infoPlist,
                variant: variant,
                linking: linking
            ) else {
                fallbackXCFrameworkPaths.insert(path)
                continue
            }

            var sdkPlan = targetPlan.sdkPlans[variant] ?? SDKPlan()
            if var existingUse = sdkPlan.frameworksByName[selectedFramework.frameworkName] {
                guard existingUse.framework == selectedFramework else {
                    fallbackXCFrameworkPaths.insert(existingUse.framework.xcframeworkPath)
                    fallbackXCFrameworkPaths.insert(selectedFramework.xcframeworkPath)
                    continue
                }
                existingUse.merge(usage: usage, status: status)
                sdkPlan.frameworksByName[selectedFramework.frameworkName] = existingUse
            } else {
                sdkPlan.frameworksByName[selectedFramework.frameworkName] = FrameworkUse(
                    framework: selectedFramework,
                    linkStatus: usage == .linkable ? status : nil,
                    runtime: usage == .runtime && selectedFramework.linking == .dynamic
                )
            }
            targetPlan.sdkPlans[variant] = sdkPlan
        }
    }

    private static func variants(platformFilters: PlatformFilters) -> [SDKVariant]? {
        var variants: Set<SDKVariant> = []
        for platformFilter in platformFilters {
            switch platformFilter {
            case .ios:
                variants.insert(.init(sdk: "iphoneos", platform: .iOS, platformVariant: nil))
                variants.insert(.init(sdk: "iphonesimulator", platform: .iOS, platformVariant: .simulator))
            case .macos:
                variants.insert(.init(sdk: "macosx", platform: .macOS, platformVariant: nil))
            case .tvos:
                variants.insert(.init(sdk: "appletvos", platform: .tvOS, platformVariant: nil))
                variants.insert(.init(sdk: "appletvsimulator", platform: .tvOS, platformVariant: .simulator))
            case .watchos:
                variants.insert(.init(sdk: "watchos", platform: .watchOS, platformVariant: nil))
                variants.insert(.init(sdk: "watchsimulator", platform: .watchOS, platformVariant: .simulator))
            case .visionos:
                variants.insert(.init(sdk: "xros", platform: .visionOS, platformVariant: nil))
                variants.insert(.init(sdk: "xrsimulator", platform: .visionOS, platformVariant: .simulator))
            case .catalyst, .driverkit:
                return nil
            }
        }
        return variants.sorted()
    }

    private func selectedFramework(
        xcframeworkPath: AbsolutePath,
        infoPlist: XCFrameworkInfoPlist,
        variant: SDKVariant,
        linking: BinaryLinking
    ) async throws -> SelectedFramework? {
        let candidates = infoPlist.libraries.filter { library in
            library.platform == variant.platform &&
                library.platformVariant == variant.platformVariant &&
                library.path.extension == "framework"
        }
        guard candidates.count == 1, let library = candidates.first else { return nil }

        let frameworkPath = xcframeworkPath
            .appending(component: library.identifier)
            .appending(try! RelativePath(validating: library.path.pathString))
        guard try await fileSystem.exists(frameworkPath, isDirectory: true) else { return nil }

        return SelectedFramework(
            xcframeworkPath: xcframeworkPath,
            frameworkPath: frameworkPath,
            frameworkName: library.binaryName,
            linking: linking
        )
    }

    private static func derivedDirectory(sourceRootPath: AbsolutePath) -> AbsolutePath {
        sourceRootPath.appending(
            components: Constants.DerivedDirectory.name,
            Self.derivedDirectoryName
        )
    }

    private static func frameworkDirectory(
        sourceRootPath: AbsolutePath,
        targetName: String,
        sdk: String
    ) -> AbsolutePath {
        derivedDirectory(sourceRootPath: sourceRootPath)
            .appending(components: sanitizedPathComponent(targetName), sdk)
    }

    private static func sanitizedPathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return String(
            value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        )
    }

    private struct RuntimeFramework {
        let path: AbsolutePath
        let name: String
    }

    private func runtimeScript(plan: TargetPlan) -> TargetScript? {
        var runtimeFrameworksBySDK: [String: [RuntimeFramework]] = [:]
        for (variant, sdkPlan) in plan.sdkPlans {
            let frameworkDirectory = Self.frameworkDirectory(
                sourceRootPath: plan.project.sourceRootPath,
                targetName: plan.target.name,
                sdk: variant.sdk
            )
            let runtimeFrameworks = sdkPlan.frameworksByName.values
                .filter(\.runtime)
                .map { frameworkUse in
                    RuntimeFramework(
                        path: frameworkDirectory.appending(component: "\(frameworkUse.framework.frameworkName).framework"),
                        name: frameworkUse.framework.frameworkName
                    )
                }
                .sorted { lhs, rhs in lhs.path.pathString < rhs.path.pathString }
            if !runtimeFrameworks.isEmpty {
                runtimeFrameworksBySDK[variant.sdk] = runtimeFrameworks
            }
        }
        guard !runtimeFrameworksBySDK.isEmpty else { return nil }

        let cases = runtimeFrameworksBySDK.keys.sorted().map { sdk -> String in
            let installCommands = runtimeFrameworksBySDK[sdk, default: []]
                .map { framework -> String in
                    let relativePath = framework.path.relative(to: plan.project.sourceRootPath).pathString
                        .replacingOccurrences(of: "\"", with: "\\\"")
                    return "    install_framework \"$SRCROOT/\(relativePath)\""
                }
                .joined(separator: "\n")
            return """
              \(sdk))
            \(installCommands)
                ;;
            """
        }
        .joined(separator: "\n")

        let runtimeFrameworks = runtimeFrameworksBySDK.values.flatMap { $0 }
        let inputPaths = runtimeFrameworks.flatMap { framework -> [String] in
            let relativePath = framework.path.relative(to: plan.project.sourceRootPath).pathString
            return [
                "$(SRCROOT)/\(relativePath)",
                "$(SRCROOT)/\(relativePath)/\(framework.name)",
                "$(SRCROOT)/\(relativePath)/Info.plist",
            ]
        }
        .uniqued()
        let outputPaths = runtimeFrameworks
            .map { framework in "${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/\(framework.name).framework" }
            .uniqued()

        return TargetScript(
            name: "Embed Preselected XCFramework Slices",
            order: .post,
            script: .embedded(
                """
                set -euo pipefail

                platform_name="${PLATFORM_NAME:-}"
                if [ -z "$platform_name" ] && [ -n "${SDKROOT:-}" ]; then
                  platform_name="$(basename "$SDKROOT")"
                  platform_name="${platform_name%.sdk}"
                  platform_name="$(printf "%s" "$platform_name" | tr '[:upper:]' '[:lower:]')"
                fi

                RSYNC_PROTECT_TMP_FILES=(--filter "P .*.??????")

                install_framework() {
                  local source="$1"
                  if [ -L "$source" ]; then
                    source="$(readlink "$source")"
                  fi

                  local name
                  name="$(basename "$source")"
                  local destination_root="$TARGET_BUILD_DIR"
                  if [ -n "${FRAMEWORKS_FOLDER_PATH:-}" ]; then
                    destination_root="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
                  fi
                  mkdir -p "$destination_root"

                  rsync --delete -av "${RSYNC_PROTECT_TMP_FILES[@]}" \\
                    --filter "- CVS/" \\
                    --filter "- .svn/" \\
                    --filter "- .git/" \\
                    --filter "- .hg/" \\
                    --filter "- Headers" \\
                    --filter "- PrivateHeaders" \\
                    --filter "- Modules" \\
                    "$source" "$destination_root"

                  local basename
                  basename="$(basename -s .framework "$source")"
                  local binary="$destination_root/$name/$basename"
                  if ! [ -r "$binary" ]; then
                    binary="$destination_root/$basename"
                  elif [ -L "$binary" ]; then
                    local dirname
                    dirname="$(dirname "$binary")"
                    binary="$dirname/$(readlink "$binary")"
                  fi

                  if [[ "$(file "$binary")" == *"dynamically linked shared library"* ]]; then
                    strip_invalid_archs "$binary"
                  fi
                  code_sign_if_enabled "$destination_root/$name"
                }

                code_sign_if_enabled() {
                  if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "${CODE_SIGNING_REQUIRED:-}" != "NO" ] && [ "${CODE_SIGNING_ALLOWED:-}" != "NO" ]; then
                    local code_sign_cmd="/usr/bin/codesign --force --sign ${EXPANDED_CODE_SIGN_IDENTITY} ${OTHER_CODE_SIGN_FLAGS:-} --preserve-metadata=identifier,entitlements '$1'"
                    echo "$code_sign_cmd"
                    eval "$code_sign_cmd"
                  fi
                }

                strip_invalid_archs() {
                  local binary="$1"
                  local binary_archs
                  binary_archs="$(lipo -info "$binary" | rev | cut -d ':' -f1 | awk '{$1=$1;print}' | rev)"
                  local intersected_archs
                  intersected_archs="$(echo ${ARCHS[@]} ${binary_archs[@]} | tr ' ' '\\n' | sort | uniq -d)"
                  if [[ -z "$intersected_archs" ]]; then
                    echo "warning: Preselected framework '$binary' contains architectures ($binary_archs) none of which match the current build architectures ($ARCHS)."
                    return
                  fi
                  local stripped=""
                  for arch in $binary_archs; do
                    if ! [[ "${ARCHS}" == *"$arch"* ]]; then
                      lipo -remove "$arch" -output "$binary" "$binary"
                      stripped="$stripped $arch"
                    fi
                  done
                  if [[ "$stripped" ]]; then
                    echo "Stripped $binary of architectures:$stripped"
                  fi
                }

                case "$platform_name" in
                \(cases)
                esac
                """
            ),
            inputPaths: inputPaths,
            outputPaths: outputPaths,
            showEnvVarsInLog: false,
            basedOnDependencyAnalysis: true,
            shellPath: "/bin/bash"
        )
    }

    private static func apply(
        _ additions: [(key: String, values: [String])],
        to settings: Settings?,
        defaultSettings: DefaultSettings
    ) -> Settings {
        let settings = settings ?? Settings(base: [:], configurations: [:], defaultSettings: defaultSettings)
        return Settings(
            base: applied(additions, to: settings.base),
            baseDebug: settings.baseDebug,
            configurations: settings.configurations.mapValues { configuration in
                guard let configuration else { return nil }
                return configuration.with(settings: applied(additions, to: configuration.settings, onlyExistingKeys: true))
            },
            defaultSettings: settings.defaultSettings,
            defaultConfiguration: settings.defaultConfiguration
        )
    }

    private static func applied(
        _ additions: [(key: String, values: [String])],
        to settings: SettingsDictionary,
        onlyExistingKeys: Bool = false
    ) -> SettingsDictionary {
        var settings = settings
        for (key, values) in additions where !values.isEmpty {
            if onlyExistingKeys, settings[key] == nil, settings[Self.rootSettingName(key)] == nil { continue }
            settings[key] = extended(settings[key], with: values)
        }
        return settings
    }

    private static func extended(_ value: SettingsDictionary.Value?, with values: [String]) -> SettingsDictionary.Value {
        switch value ?? .array(["$(inherited)"]) {
        case let .array(existing):
            return .array((existing + values).uniqued())
        case let .string(existing):
            return .array((existing.split(separator: " ").map(String.init) + values).uniqued())
        }
    }

    private static func rootSettingName(_ key: String) -> String {
        key.split(separator: "[").first.map(String.init) ?? key
    }
}

private extension Graph {
    var linkingByXCFrameworkPath: [AbsolutePath: BinaryLinking] {
        var linkingByPath: [AbsolutePath: BinaryLinking] = [:]
        for dependency in Set(dependencies.keys).union(dependencies.values.flatMap { $0 }) {
            if case let .xcframework(xcframework) = dependency {
                linkingByPath[xcframework.path] = xcframework.linking
            }
        }
        return linkingByPath
    }

    func removingXCFrameworkDependencies(at paths: Set<AbsolutePath>) -> Graph {
        var graph = self
        graph.dependencies = Dictionary(uniqueKeysWithValues: dependencies.compactMap { dependency, dependencyValues in
            guard !dependency.isXCFramework(at: paths) else { return nil }
            let filteredDependencies = dependencyValues.filter { !$0.isXCFramework(at: paths) }
            return (dependency, filteredDependencies)
        })
        graph.dependencyConditions = dependencyConditions.filter { edge, _ in
            !edge.from.isXCFramework(at: paths) && !edge.to.isXCFramework(at: paths)
        }
        return graph
    }
}

private extension GraphDependency {
    func isXCFramework(at paths: Set<AbsolutePath>) -> Bool {
        guard case let .xcframework(xcframework) = self else { return false }
        return paths.contains(xcframework.path)
    }
}
