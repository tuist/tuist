import Foundation

/// Swift representation of the JSON schema Xcode uses for `.xctestplan` files.
///
/// Fields that don't apply to a particular use-case (reading an existing plan vs. generating
/// a new one) are modelled as optionals so that encoders can omit them and decoders can
/// tolerate their absence.
public struct XCTestPlan: Codable, Equatable, Sendable {
    public struct Configuration: Codable, Equatable, Sendable {
        public let id: UUID
        public let name: String
        public let options: [String: String]

        public init(id: UUID, name: String, options: [String: String] = [:]) {
            self.id = id
            self.name = name
            self.options = options
        }
    }

    public struct TestTargetReference: Codable, Equatable, Sendable {
        /// Path to the target's container, prefixed with `container:` (e.g. `container:App.xcodeproj`).
        public let containerPath: String

        /// Blueprint identifier of the PBX target the entry references.
        public let identifier: String

        /// Name of the test target.
        public let name: String

        public init(containerPath: String, identifier: String, name: String) {
            self.containerPath = containerPath
            self.identifier = identifier
            self.name = name
        }
    }

    public struct TestTarget: Codable, Equatable, Sendable {
        /// Whether the target runs. Omitted in the JSON when `true`; Xcode defaults to enabled.
        public let enabled: Bool?

        /// Whether the target runs in parallel with other targets.
        public let parallelizable: Bool?

        public let target: TestTargetReference

        public init(
            target: TestTargetReference,
            enabled: Bool? = nil,
            parallelizable: Bool? = nil
        ) {
            self.enabled = enabled
            self.parallelizable = parallelizable
            self.target = target
        }
    }

    public let configurations: [Configuration]?
    public let defaultOptions: [String: String]?
    public let testTargets: [TestTarget]
    public let version: Int?

    public init(
        testTargets: [TestTarget],
        configurations: [Configuration]? = nil,
        defaultOptions: [String: String]? = nil,
        version: Int? = nil
    ) {
        self.configurations = configurations
        self.defaultOptions = defaultOptions
        self.testTargets = testTargets
        self.version = version
    }
}
