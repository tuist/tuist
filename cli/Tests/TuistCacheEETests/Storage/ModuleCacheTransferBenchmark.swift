import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistCache
import TuistCore
import TuistEnvironmentTesting
import TuistREAPI
import TuistServer

@testable import TuistCacheEE

/// Opt-in benchmark of the real archive and REAPI storage clients against the same Kura node.
struct ModuleCacheTransferBenchmark {
    private struct Configuration: Decodable {
        let endpoint: URL
        let token: String
        let account: String
        let inputs: String
        let output: String
        let repetitions: Int
        let project: String?
        let authenticationURL: URL?
        let metricsURL: URL?
        let runID: String?
        let independentRepetitionInputs: Bool?
    }

    private struct Measurement: Encodable {
        let corpus: String
        let model: String
        let repetition: Int
        let phase: String
        let seconds: Double
        let counters: [String: Double]
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .enabled(if: ProcessInfo.processInfo.environment["TUIST_MODULE_CACHE_BENCHMARK_CONFIG"] != nil)
    )
    func compareTransfers() async throws {
        let fileSystem = FileSystem()
        let configPath = try #require(ProcessInfo.processInfo.environment["TUIST_MODULE_CACHE_BENCHMARK_CONFIG"])
        let config = try JSONDecoder().decode(
            Configuration.self,
            from: await fileSystem.readFile(at: AbsolutePath(validating: configPath))
        )
        let root = try #require(FileSystem.temporaryTestDirectory)
        let runID = config.runID ?? UUID().uuidString
        let authenticationURL = config.authenticationURL ?? config.endpoint
        let output = try AbsolutePath(validating: config.output)
        try await fileSystem.makeDirectory(at: output)
        let authentication = MockServerAuthenticationControlling()
        given(authentication).authenticationToken(serverURL: .any).willReturn(.project(config.token))
        given(authentication).authenticationToken(serverURL: .any, refreshIfNeeded: .any).willReturn(.project(config.token))
        var measurements: [Measurement] = []
        let corpora = try await fileSystem.contentsOfDirectory(AbsolutePath(validating: config.inputs)).sorted()
        for corpus in corpora {
            for repetition in 0 ..< config.repetitions {
                let input = config.independentRepetitionInputs == true
                    ? corpus.appending(component: String(repetition)) : corpus
                let artifacts = try await fileSystem.contentsOfDirectory(input).filter { $0.extension == "xcframework" }.sorted()
                try #require(!artifacts.isEmpty)
                let namespace = "\(runID)-\(corpus.basename)-\(repetition)"
                let items = Dictionary(uniqueKeysWithValues: artifacts.map { artifact in
                    let name = artifact.basenameWithoutExt
                    return (
                        CacheStorableItem(name: name, hash: REAPI.digest(Data("\(namespace)-\(name)".utf8)).hash, metadata: .init(
                            binaryCacheFingerprints: Dictionary(uniqueKeysWithValues: [
                                "ios-device",
                                "ios-simulator",
                                "macos-device",
                            ]
                            .map {
                                ($0, REAPI.digest(Data("\(namespace)-\(name)-\($0)".utf8)).hash)
                            })
                        )),
                        [artifact]
                    )
                })
                for model in repetition.isMultiple(of: 2) ? ["archive", "reapi"] : ["reapi", "archive"] {
                    let project = config.project ?? "\(corpus.basename)-\(repetition)-\(model)"
                    let client = try await REAPICacheClient(
                        endpoint: .init(
                            host: try #require(config.endpoint.host),
                            explicitPort: config.endpoint.port,
                            isTLS: config.endpoint.scheme == "https"
                        ),
                        accountHandle: config.account,
                        instanceName: project
                    ) { config.token }
                    if model == "reapi" { try await client.validateCapabilities() }
                    // Both transports receive the same pre-exchanged credential, outside the timed phases.
                    let _: String? = try await CachedValueStore.current.getValue(
                        key: "cache-token-\(authenticationURL.absoluteString)-\(config.account)/\(project)"
                    ) { (value: config.token, expiresAt: Date().addingTimeInterval(3600)) }
                    _ = try await CacheTokenStore.shared.cacheToken(
                        authenticationURL: authenticationURL, fullHandle: "\(config.account)/\(project)"
                    )
                    for phase in ["cold-push", "existing-push", "cold-pull", "ios-pull"] {
                        let directory = root.appending(component: "\(project)-\(phase)")
                        let provider = MockCacheDirectoriesProviding()
                        given(provider).cacheDirectory(for: .any).willReturn(directory)
                        let local = CacheLocalStorage(cacheDirectoriesProvider: provider)
                        let storage: any CacheStoring
                        if model == "archive" {
                            storage = CacheStorage(localStorage: local, remoteStorage: ModuleCacheRemoteStorage(
                                fullHandle: "\(config.account)/\(project)", cacheURL: config.endpoint,
                                serverURL: authenticationURL,
                                serverAuthenticationController: authentication, cacheDirectoriesProvider: provider,
                                concurrencyLimit: 100, cacheActionItemConcurrencyLimit: 30
                            ))
                        } else {
                            storage = BinaryCacheStorage(
                                selectiveTestsStorage: local, local: BinaryCacheLocalStore(directory: directory), remote: client
                            )
                        }
                        let requested = Set(items.keys.map { item in
                            if phase == "ios-pull", model == "reapi" {
                                return CacheStorableItem(name: item.name, hash: item.hash + "-ios", metadata: .init(
                                    binaryCacheFingerprints: item.metadata.binaryCacheFingerprints
                                        .filter { $0.key != "macos-device" }
                                ))
                            }
                            return item
                        })
                        let before = try await metrics(config.metricsURL)
                        let clock = ContinuousClock()
                        let start = clock.now
                        var restored: [CacheItem: AbsolutePath] = [:]
                        if phase.hasSuffix("push") {
                            let stored = try await storage.store(items, cacheCategory: .binaries)
                            try #require(stored.count == items.count)
                        } else {
                            restored = try await storage.fetch(requested, cacheCategory: .binaries)
                            try #require(restored.count == items.count)
                        }
                        let elapsed = start.duration(to: clock.now).components
                        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                        let after = try await metrics(config.metricsURL)
                        let delta = after.reduce(into: [String: Double]()) { result, pair in
                            let value = pair.value - (before[pair.key] ?? 0)
                            if value != 0 { result[pair.key] = value }
                        }
                        measurements.append(.init(
                            corpus: corpus.basename, model: model, repetition: repetition, phase: phase,
                            seconds: seconds, counters: delta
                        ))
                        print("TRANSFER_BENCHMARK \(project) \(phase): \(seconds)s \(delta)")
                        for (item, path) in restored {
                            let source = try #require(artifacts.first { $0.basenameWithoutExt == item.name })
                            let coverage = try await XCFrameworkCoverageService().coverage(at: path)
                            let iosOnly = phase == "ios-pull" && model == "reapi"
                            try #require(Set(coverage.keys) == Set(iosOnly
                                    ? ["ios-device", "ios-simulator"] : ["ios-device", "ios-simulator", "macos-device"]))
                            for file in try await fileSystem.glob(directory: source, include: ["**/*"]).collect() {
                                let relative = file.relative(to: source)
                                if relative.pathString == "Info.plist" { continue }
                                if iosOnly, relative.pathString.hasPrefix("macos-") { continue }
                                let attributes = try file.url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                                if attributes.isRegularFile == true, attributes.isSymbolicLink != true {
                                    let expected = try REAPI.digest(file: file.url)
                                    let actual = try REAPI.digest(file: path.appending(relative).url)
                                    try #require(actual == expected)
                                }
                            }
                        }
                        try await fileSystem.writeAsJSON(measurements, at: output.appending(component: "results.json"))
                        try await fileSystem.remove(directory)
                    }
                }
            }
        }
    }

    private func metrics(_ url: URL?) async throws -> [String: Double] {
        guard let url else { return [:] }
        let (data, response) = try await URLSession.shared.data(from: url)
        try #require((response as? HTTPURLResponse)?.statusCode == 200)
        var result: [String: Double] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let fields = line.split(separator: " ")
            guard fields.count == 2, let value = Double(fields[1]),
                  [
                      "tuist_benchmark_wire_",
                      "kura_artifact_write_bytes_total",
                      "kura_artifact_read_bytes_total",
                      "kura_artifact_egress_bytes_total",
                      "kura_public_request_latency_seconds_count"
                  ]
                  .contains(where: { fields[0].hasPrefix($0) }) else { continue }
            result[String(fields[0])] = value
        }
        return result
    }
}
