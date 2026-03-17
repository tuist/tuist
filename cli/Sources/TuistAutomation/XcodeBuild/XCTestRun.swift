#if os(macOS)
    import Foundation

    public struct XCTestRun: Decodable, Equatable {
        public let testConfigurations: [TestConfiguration]

        enum CodingKeys: String, CodingKey {
            case testConfigurations = "TestConfigurations"
        }

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
    }
#endif
