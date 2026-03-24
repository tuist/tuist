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

        enum CodingKeys: String, CodingKey {
            case blueprintName = "BlueprintName"
            case onlyTestIdentifiers = "OnlyTestIdentifiers"
        }
    }

    public var testModules: [String] {
        testConfigurations
            .flatMap { $0.testTargets ?? [] }
            .map(\.blueprintName)
    }

    private struct NewFormat: Decodable {
        let testConfigurations: [TestConfiguration]

        enum CodingKeys: String, CodingKey {
            case testConfigurations = "TestConfigurations"
        }
    }

    private struct LegacyEntry: Decodable {
        let blueprintName: String

        enum CodingKeys: String, CodingKey {
            case blueprintName = "BlueprintName"
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
            targets.append(TestTarget(blueprintName: entry.blueprintName, onlyTestIdentifiers: nil))
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
