import Foundation

public struct XCTestRun: Decodable, Equatable {
    public let testConfigurations: [TestConfiguration]

    public struct TestConfiguration: Decodable, Equatable {
        public let testTargets: [TestTarget]?

        enum CodingKeys: String, CodingKey {
            case testTargets = "TestTargets"
        }
    }

    public struct TestTarget: Decodable, Equatable {
        public let blueprintName: String
        public let onlyTestIdentifiers: [String]?
        /// Whether xcodebuild runs this target's tests across multiple runner processes. Absent in
        /// the legacy format and in bundles produced before Xcode wrote the key, which is why it is
        /// optional rather than defaulted: a missing value means "not stated", not "disabled".
        public let parallelizationEnabled: Bool?

        public init(blueprintName: String, onlyTestIdentifiers: [String]?, parallelizationEnabled: Bool? = nil) {
            self.blueprintName = blueprintName
            self.onlyTestIdentifiers = onlyTestIdentifiers
            self.parallelizationEnabled = parallelizationEnabled
        }

        enum CodingKeys: String, CodingKey {
            case blueprintName = "BlueprintName"
            case onlyTestIdentifiers = "OnlyTestIdentifiers"
            case parallelizationEnabled = "ParallelizationEnabled"
        }
    }

    public var testModules: [String] {
        testConfigurations
            .flatMap { $0.testTargets ?? [] }
            .map(\.blueprintName)
    }

    /// The suites the built products limit a module to, as `Module/Suite`. A test plan that selects
    /// specific tests bakes the selection into the bundle, so what will run is known exactly and
    /// doesn't have to be inferred from what previous runs happened to execute. A module that is
    /// limited to nothing contributes no entries and is left to be resolved from history.
    ///
    /// Identifiers naming a single test are collapsed to the suite that holds it, since a plan
    /// distributes suites.
    public func selectedTestSuiteIdentifiers() -> [String] {
        let identifiers = testConfigurations
            .flatMap { $0.testTargets ?? [] }
            .flatMap { target in
                (target.onlyTestIdentifiers ?? []).map { identifier in
                    let suite = identifier.split(separator: "/").first.map(String.init) ?? identifier
                    return "\(target.blueprintName)/\(suite)"
                }
            }
        return Set(identifiers).sorted()
    }

    /// Modules xcodebuild will run with test parallelization on. A module enabled in any
    /// configuration counts, since that is enough for its suites to overlap in the run.
    public var parallelizableTestModules: [String] {
        let names = testConfigurations
            .flatMap { $0.testTargets ?? [] }
            .filter { $0.parallelizationEnabled == true }
            .map(\.blueprintName)
        return Array(Set(names)).sorted()
    }

    private struct NewFormat: Decodable {
        let testConfigurations: [TestConfiguration]

        enum CodingKeys: String, CodingKey {
            case testConfigurations = "TestConfigurations"
        }
    }

    private struct LegacyEntry: Decodable {
        let blueprintName: String
        let parallelizationEnabled: Bool?

        enum CodingKeys: String, CodingKey {
            case blueprintName = "BlueprintName"
            case parallelizationEnabled = "ParallelizationEnabled"
        }
    }

    public init(from decoder: Decoder) throws {
        if let newFormat = try? NewFormat(from: decoder) {
            testConfigurations = newFormat.testConfigurations
            return
        }

        // Legacy xctestrun format (v1): test targets are top-level keys (e.g. 'AppTests', 'CoreTests'),
        // with '__xctestrun_metadata__' as the metadata key. Used by projects without test plans.
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var targets: [TestTarget] = []
        for key in container.allKeys {
            if key.stringValue.hasPrefix("__") { continue }
            guard let entry = try? container.decode(LegacyEntry.self, forKey: key) else { continue }
            targets.append(
                TestTarget(
                    blueprintName: entry.blueprintName,
                    onlyTestIdentifiers: nil,
                    parallelizationEnabled: entry.parallelizationEnabled
                )
            )
        }
        testConfigurations = [TestConfiguration(testTargets: targets)]
    }

    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { self.intValue = intValue; stringValue = "\(intValue)" }
    }
}
