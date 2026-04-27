#if os(macOS)
    import TuistCore
    import TuistLoader
    import XcodeGraph

    enum InspectType {
        case redundant
        case implicit
    }

    protocol GraphImportsLinting {
        func lint(
            graphTraverser: GraphTraverser,
            inspectType: InspectType,
            ignoreTagsMatching: Set<String>
        ) async throws -> [InspectImportsIssue]
    }

    struct GraphImportsLinter: GraphImportsLinting {
        private let targetScanner: TargetImportsScanning

        init(targetScanner: TargetImportsScanning = TargetImportsScanner()) {
            self.targetScanner = targetScanner
        }

        func lint(
            graphTraverser: GraphTraverser,
            inspectType: InspectType,
            ignoreTagsMatching: Set<String>
        ) async throws -> [InspectImportsIssue] {
            return try await targetImportsMap(graphTraverser: graphTraverser, inspectType: inspectType)
                .sorted { $0.key.productName < $1.key.productName }
                .compactMap { target, dependencies in
                    guard target.metadata.tags.intersection(ignoreTagsMatching).isEmpty else {
                        return nil
                    }
                    return InspectImportsIssue(target: target.productName, dependencies: dependencies)
                }
        }

        private func targetImportsMap(
            graphTraverser: GraphTraverser,
            inspectType: InspectType
        ) async throws -> [Target: Set<String>] {
            let allInternalTargets = graphTraverser
                .allInternalTargets()
            let allTargets = allInternalTargets
                .union(graphTraverser.allExternalTargets())
                .filter {
                    switch inspectType {
                    case .redundant:
                        return switch $0.target.product {
                        case .staticLibrary, .staticFramework, .dynamicLibrary, .framework, .app: true
                        default: false
                        }
                    case .implicit:
                        return true
                    }
                }
            var observedTargetImports: [Target: Set<String>] = [:]

            let allTargetNames = Set(allTargets.map(\.target.productName))

            for target in allInternalTargets {
                let context = compilationConditionContext(
                    for: target,
                    graphTraverser: graphTraverser,
                    allTargetNames: allTargetNames
                )
                let sourceDependencies = Set(try await targetScanner.imports(for: target.target, context: context))

                let explicitTargetDependencies = explicitTargetDependencies(
                    graphTraverser: graphTraverser,
                    target: target,
                    includeExternalDependencies: inspectType == .implicit,
                    excludeAppDependenciesForTests: inspectType == .redundant
                )

                let observedImports = switch inspectType {
                case .redundant:
                    explicitTargetDependencies.subtracting(sourceDependencies)
                case .implicit:
                    sourceDependencies.subtracting(explicitTargetDependencies)
                        .intersection(allTargetNames)
                }
                if !observedImports.isEmpty {
                    observedTargetImports[target.target] = observedImports
                }
            }
            return observedTargetImports
        }

        private func explicitTargetDependencies(
            graphTraverser: GraphTraverser,
            target: GraphTarget,
            includeExternalDependencies: Bool,
            excludeAppDependenciesForTests: Bool
        ) -> Set<String> {
            let targetDependencies = if includeExternalDependencies {
                graphTraverser
                    .directTargetDependencies(path: target.project.path, name: target.target.name)
            } else {
                graphTraverser
                    .directNonExternalTargetDependencies(path: target.project.path, name: target.target.name)
            }

            let explicitTargetDependencies = targetDependencies
                .filter { dependency in
                    !dependency.target.bundleId.hasSuffix(".generated.resources")
                }
                .filter { dependency in
                    dependency.target.product != .macro
                }
                .filter { dependency in
                    switch target.target.product {
                    case .app, .watch2AppContainer:
                        switch dependency.target.product {
                        case .appExtension, .stickerPackExtension, .messagesExtension, .extensionKitExtension, .watch2App:
                            return false
                        case .app, .watch2AppContainer, .staticLibrary, .dynamicLibrary, .framework, .staticFramework, .unitTests,
                             .uiTests, .bundle, .commandLineTool, .watch2Extension, .tvTopShelfExtension, .appClip, .xpc,
                             .systemExtension, .macro:
                            return true
                        }
                    case .watch2App:
                        switch dependency.target.product {
                        case .watch2Extension:
                            return false
                        case .app, .watch2AppContainer, .staticLibrary, .dynamicLibrary, .framework, .staticFramework, .unitTests,
                             .uiTests, .bundle, .commandLineTool, .tvTopShelfExtension, .appClip, .xpc, .systemExtension, .macro,
                             .appExtension, .stickerPackExtension, .messagesExtension, .extensionKitExtension, .watch2App:
                            return true
                        }
                    case .unitTests, .uiTests:
                        switch dependency.target.product {
                        case .app:
                            return !excludeAppDependenciesForTests
                        case .watch2AppContainer, .staticLibrary, .dynamicLibrary, .framework, .staticFramework, .unitTests,
                             .uiTests, .bundle, .commandLineTool, .tvTopShelfExtension, .appClip, .xpc, .systemExtension, .macro,
                             .appExtension, .stickerPackExtension, .messagesExtension, .extensionKitExtension, .watch2App,
                             .watch2Extension:
                            return true
                        }
                    case .staticLibrary, .dynamicLibrary, .framework, .staticFramework, .bundle,
                         .commandLineTool, .tvTopShelfExtension, .appClip, .xpc, .systemExtension, .macro, .appExtension,
                         .stickerPackExtension, .messagesExtension, .extensionKitExtension, .watch2Extension:
                        return true
                    }
                }
                .map { dependency in
                    if case .external = dependency.graphTarget.project.type {
                        let targets = [dependency.graphTarget] + graphTraverser.allTargetDependencies(
                            path: dependency.graphTarget.project.path,
                            name: dependency.graphTarget.target.name
                        )
                        return Set(targets)
                    } else {
                        return Set(arrayLiteral: dependency.graphTarget)
                    }
                }
                .flatMap { $0 }
                .map(\.target.productName)
            return Set(explicitTargetDependencies)
        }

        private func compilationConditionContext(
            for target: GraphTarget,
            graphTraverser: GraphTraverser,
            allTargetNames: Set<String>
        ) -> CompilationConditionContext {
            let flagSets = activeCompilationConditionSets(for: target)
            let platforms = Set(target.target.destinations.map(\.platform).map(platformIdentifier))
            let environments = targetEnvironments(for: target.target)

            // Reachable modules drive `canImport(...)`. We use the transitive declared
            // dependency closure mapped to product names. Crucially we only count
            // modules that exist as targets in this graph — that matches Swift's
            // compile-time view, where `canImport(X)` is true iff X is in the
            // module search path the build is being constructed with.
            let transitive = graphTraverser.allTargetDependencies(
                path: target.path,
                name: target.target.name
            )
            let reachable = Set(transitive.map(\.target.productName))
                .intersection(allTargetNames)

            return CompilationConditionContext(
                flagSetsPerConfiguration: flagSets,
                platforms: platforms,
                architectures: [],
                targetEnvironments: environments,
                reachableModules: reachable
            )
        }

        private func activeCompilationConditionSets(for target: GraphTarget) -> [Set<String>] {
            var sets: [Set<String>] = []
            let baseFlags = compilationConditions(in: target.target.settings?.base ?? [:])
            let configurations = target.target.settings?.configurations ?? [:]
            if configurations.isEmpty {
                sets.append(baseFlags)
            } else {
                for (_, configuration) in configurations {
                    let configFlags = compilationConditions(in: configuration?.settings ?? [:])
                    sets.append(baseFlags.union(configFlags))
                }
            }
            return sets.isEmpty ? [[]] : sets
        }

        private func compilationConditions(in settings: SettingsDictionary) -> Set<String> {
            guard let value = settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] else { return [] }
            switch value {
            case let .string(string):
                return Set(string.split(separator: " ").map(String.init).filter { $0 != "$(inherited)" })
            case let .array(values):
                return Set(values.filter { $0 != "$(inherited)" })
            }
        }

        private func platformIdentifier(_ platform: Platform) -> String {
            // Swift's `os(...)` directive uses these identifiers. Mapping is exhaustive
            // for platforms Tuist supports.
            switch platform {
            case .iOS: return "iOS"
            case .macOS: return "macOS"
            case .tvOS: return "tvOS"
            case .watchOS: return "watchOS"
            case .visionOS: return "visionOS"
            }
        }

        private func targetEnvironments(for target: Target) -> Set<String> {
            var environments: Set<String> = []
            if target.destinations.contains(.macCatalyst) {
                environments.insert("macCatalyst")
            }
            // Simulator destinations cover the simulator environment for non-Mac platforms.
            // We treat the presence of any non-Mac destination as "may run on simulator"
            // since Tuist destinations don't model simulator vs device explicitly.
            let simulatorPlatforms: Set<Platform> = [.iOS, .tvOS, .watchOS, .visionOS]
            if target.destinations.map(\.platform).contains(where: { simulatorPlatforms.contains($0) }) {
                environments.insert("simulator")
            }
            return environments
        }
    }
#endif
