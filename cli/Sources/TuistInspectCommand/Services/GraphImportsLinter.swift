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
            let allModuleNames = allTargetNames.union(precompiledModuleNames(graphTraverser: graphTraverser))

            for target in allInternalTargets {
                let reachableModules = reachableModules(
                    for: target,
                    graphTraverser: graphTraverser,
                    allModuleNames: allModuleNames
                )
                let sourceDependencies = Set(
                    try await targetScanner.imports(for: target.target, reachableModules: reachableModules)
                )

                let explicitDependencyModules = explicitDependencyModules(
                    graphTraverser: graphTraverser,
                    target: target,
                    includeExternalDependencies: inspectType == .implicit,
                    excludeAppDependenciesForTests: inspectType == .redundant
                )

                let observedImports = switch inspectType {
                case .redundant:
                    explicitDependencyModules.subtracting(sourceDependencies)
                case .implicit:
                    sourceDependencies.subtracting(explicitDependencyModules)
                        .intersection(allModuleNames)
                }
                if !observedImports.isEmpty {
                    observedTargetImports[target.target] = observedImports
                }
            }
            return observedTargetImports
        }

        private func explicitDependencyModules(
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
                        let graphDependency = GraphDependency.target(
                            name: dependency.graphTarget.target.name,
                            path: dependency.graphTarget.project.path
                        )
                        return Set([dependency.graphTarget.target.productName])
                            .union(
                                transitiveDependencies(
                                    from: graphDependency,
                                    graphTraverser: graphTraverser
                                )
                                .flatMap { moduleNames(for: $0, graphTraverser: graphTraverser) }
                            )
                    } else {
                        return Set(arrayLiteral: dependency.graphTarget.target.productName)
                    }
                }
                .flatMap { $0 }
            var explicitDependencyModules = Set(explicitTargetDependencies)

            if includeExternalDependencies {
                let graphDependency = GraphDependency.target(name: target.target.name, path: target.project.path)
                let directPrecompiledDependencyModules = graphTraverser.dependencies[graphDependency, default: []]
                    .filter { !$0.isTarget }
                    .flatMap { moduleNames(for: $0, graphTraverser: graphTraverser) }
                explicitDependencyModules.formUnion(directPrecompiledDependencyModules)
            }

            return explicitDependencyModules
        }

        /// Modules reachable from the target's transitive declared-dependency closure.
        /// Used to evaluate `#if canImport(X)` the same way the compiler would: `X` is
        /// reachable iff it sits in this target's declared dep graph.
        private func reachableModules(
            for target: GraphTarget,
            graphTraverser: GraphTraverser,
            allModuleNames: Set<String>
        ) -> Set<String> {
            let graphDependency = GraphDependency.target(name: target.target.name, path: target.path)
            return Set(
                transitiveDependencies(from: graphDependency, graphTraverser: graphTraverser)
                    .flatMap { moduleNames(for: $0, graphTraverser: graphTraverser) }
            )
            .intersection(allModuleNames)
        }

        private func precompiledModuleNames(graphTraverser: GraphTraverser) -> Set<String> {
            var dependencies = Set(graphTraverser.dependencies.keys)
            graphTraverser.dependencies.values.forEach { dependencies.formUnion($0) }
            return Set(
                dependencies
                    .filter { !$0.isTarget }
                    .flatMap { moduleNames(for: $0, graphTraverser: graphTraverser) }
            )
        }

        private func transitiveDependencies(
            from root: GraphDependency,
            graphTraverser: GraphTraverser
        ) -> Set<GraphDependency> {
            var visited: Set<GraphDependency> = []
            var stack = Array(graphTraverser.dependencies[root, default: []])

            while let dependency = stack.popLast() {
                guard visited.insert(dependency).inserted else { continue }
                stack.append(contentsOf: graphTraverser.dependencies[dependency, default: []])
            }

            return visited
        }

        private func moduleNames(
            for dependency: GraphDependency,
            graphTraverser: GraphTraverser
        ) -> Set<String> {
            switch dependency {
            case let .target(name, path, _):
                guard let target = graphTraverser.target(path: path, name: name) else { return [] }
                return [target.target.productName]
            case let .xcframework(xcframework):
                return Set(xcframework.infoPlist.libraries.map(\.binaryName))
            case let .framework(path, _, _, _, _, _, _):
                return [path.basenameWithoutExt]
            case let .foreignBuildOutput(output):
                return [output.name]
            case let .packageProduct(_, product, _):
                return [product]
            case .bundle, .library, .macro, .sdk:
                return []
            }
        }
    }
#endif
