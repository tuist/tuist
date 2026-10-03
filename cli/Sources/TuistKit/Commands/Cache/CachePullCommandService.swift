#if canImport(TuistCacheEE)
    import Foundation
    import Path
    import TuistCache
    import TuistCacheEE
    import TuistConfig
    import TuistConfigLoader
    import TuistCore
    import TuistEnvironment
    import TuistExtension
    import TuistHasher
    import TuistLoader
    import TuistLogging
    import TuistServer
    import XcodeGraph

    enum CachePullCommandServiceError: LocalizedError, Equatable {
        case generatedProjectNotFound(AbsolutePath)
        case targetsNotFound([String])
        case noCacheableTargets([String])

        var errorDescription: String? {
            switch self {
            case let .generatedProjectNotFound(path):
                return "We couldn't find a generated project at \(path.pathString). Binary caching only works with generated projects."
            case let .targetsNotFound(targets):
                return "We couldn't find the requested targets in the graph: \(targets.joined(separator: ", "))."
            case let .noCacheableTargets(targets):
                return "The requested targets don't include any cacheable binaries: \(targets.joined(separator: ", "))."
            }
        }
    }

    public struct CachePullCommandService: CachePullServicing {
        private let generatorFactory: CacheGeneratorFactorying
        private let cacheGraphContentHasher: CacheGraphContentHashing
        private let cacheStorageFactory: CacheStorageFactorying
        private let configLoader: ConfigLoading
        private let manifestLoader: ManifestLoading

        public init(contentHasher: ContentHashing = CachedContentHasher()) {
            self.init(
                generatorFactory: CacheGeneratorFactory(contentHasher: contentHasher),
                cacheGraphContentHasher: CacheGraphContentHasher(contentHasher: contentHasher),
                cacheStorageFactory: Extension.cacheStorageFactory,
                configLoader: ConfigLoader(),
                manifestLoader: ManifestLoader.current
            )
        }

        init(
            generatorFactory: CacheGeneratorFactorying,
            cacheGraphContentHasher: CacheGraphContentHashing,
            cacheStorageFactory: CacheStorageFactorying,
            configLoader: ConfigLoading,
            manifestLoader: ManifestLoading
        ) {
            self.generatorFactory = generatorFactory
            self.cacheGraphContentHasher = cacheGraphContentHasher
            self.cacheStorageFactory = cacheStorageFactory
            self.configLoader = configLoader
            self.manifestLoader = manifestLoader
        }

        public func run(
            path directory: String?,
            configuration: String?,
            targets: Set<String>
        ) async throws {
            let path = try await Environment.current.pathRelativeToWorkingDirectory(directory)
            guard try await manifestLoader.hasRootManifest(at: path) else {
                throw CachePullCommandServiceError.generatedProjectNotFound(path)
            }

            let config = try await configLoader.loadConfig(path: path)
            let generator = generatorFactory.binaryCacheWarmingPreload(
                config: config,
                targetsToBinaryCache: []
            )
            let graph = try await generator.load(
                path: path,
                options: config.project.generatedProject?.generationOptions
            )
            let hashes = try await cacheGraphContentHasher.contentHashes(
                for: graph,
                configuration: configuration,
                defaultConfiguration: config.project.generatedProject?.generationOptions.defaultConfiguration,
                excludedTargets: [],
                destination: nil
            )
            let selectedHashes = try selectedHashes(
                from: hashes,
                graph: graph,
                requestedTargets: targets
            )

            guard !selectedHashes.isEmpty else {
                if !targets.isEmpty {
                    throw CachePullCommandServiceError.noCacheableTargets(targets.sorted())
                }
                Logger.current.info("The project contains no cacheable targets")
                return
            }

            let items = Set(selectedHashes.map {
                CacheStorableItem(name: $0.key.target.name, hash: $0.value.hash)
            })
            let cacheStorage = try await cacheStorageFactory.cacheStorage(config: config)
            let pulledBinaries = try await cacheStorage.fetch(items, cacheCategory: .binaries)
            let pulledItems = Set(pulledBinaries.keys.map {
                CacheStorableItem(name: $0.name, hash: $0.hash)
            })
            let missingItems = items.subtracting(pulledItems)

            logSummary(pulledBinaries: pulledBinaries, missingItems: missingItems)
        }

        private func selectedHashes(
            from hashes: [GraphTarget: TargetContentHash],
            graph: Graph,
            requestedTargets: Set<String>
        ) throws -> [GraphTarget: TargetContentHash] {
            guard !requestedTargets.isEmpty else { return hashes }

            let graphTraverser = GraphTraverser(graph: graph)
            let requestedGraphTargets = graphTraverser.filterIncludedTargets(
                basedOn: graphTraverser.allTargets(),
                testPlan: nil,
                includedTargets: Set(requestedTargets.map { TargetQuery(stringLiteral: $0) }),
                excludedTargets: []
            )
            guard !requestedGraphTargets.isEmpty else {
                throw CachePullCommandServiceError.targetsNotFound(requestedTargets.sorted())
            }

            let nonTestRoots = requestedGraphTargets.filter { !$0.target.product.testsBundle }
            guard !nonTestRoots.isEmpty else {
                throw CachePullCommandServiceError.noCacheableTargets(requestedTargets.sorted())
            }

            let selectedTargets = graphTraverser
                .allTargetDependencies(traversingFromTargets: Array(nonTestRoots))
                .union(nonTestRoots)
            return hashes.filter { selectedTargets.contains($0.key) }
        }

        private func logSummary(
            pulledBinaries: [CacheItem: AbsolutePath],
            missingItems: Set<CacheStorableItem>
        ) {
            let localCount = pulledBinaries.keys.count(where: { $0.source == .local })
            let remoteCount = pulledBinaries.keys.count(where: { $0.source == .remote })
            Logger.current.info(
                "Pulled \(remoteCount) binaries, found \(localCount) locally, and missed \(missingItems.count)."
            )
        }
    }
#endif
