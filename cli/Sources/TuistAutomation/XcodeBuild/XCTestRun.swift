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
