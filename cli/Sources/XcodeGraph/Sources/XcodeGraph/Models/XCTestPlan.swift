@preconcurrency import AnyCodable
import Foundation

/// Swift representation of the JSON schema Xcode uses for `.xctestplan` files.
///
/// Fields that don't apply to a particular use-case (reading an existing plan vs. generating
/// a new one) are modelled as optionals so that encoders can omit them and decoders can
/// tolerate their absence. The `options` / `defaultOptions` payloads are modelled as
/// `[String: AnyCodable]` because Xcode stores a mix of booleans, strings, and nested target
/// references there.
public struct XCTestPlan: Codable, Equatable, Sendable {
    public struct Configuration: Codable, Equatable, Sendable {
        public let id: UUID
        public let name: String
        public let options: [String: AnyCodable]

        public init(id: UUID, name: String, options: [String: AnyCodable] = [:]) {
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

    /// A Swift Testing tag filter, matching the shape Xcode writes:
    /// `"selectedTags" : { "tags" : [ ".contract" ] }`. Tag names carry the leading dot.
    public struct TagList: Codable, Equatable, Sendable {
        public let tags: [String]

        public init(tags: [String]) {
            self.tags = tags
        }
    }

    public struct TestTarget: Codable, Equatable, Sendable {
        /// Whether the target runs. Omitted in the JSON when `true`; Xcode defaults to enabled.
        public let enabled: Bool?

        /// Whether the target runs in parallel with other targets.
        public let parallelizable: Bool?

        public let target: TestTargetReference

        /// Tags whose tests are the only ones the target runs, written as
        /// `"selectedTags" : { "tags" : [ ".contract" ] }`. Omitted from the JSON when `nil`.
        public let selectedTags: TagList?

        /// Tags whose tests the target skips, written as
        /// `"skippedTags" : { "tags" : [ ".contract" ] }`. Omitted from the JSON when `nil`.
        public let skippedTags: TagList?

        public init(
            target: TestTargetReference,
            enabled: Bool? = nil,
            parallelizable: Bool? = nil,
            selectedTags: TagList? = nil,
            skippedTags: TagList? = nil
        ) {
            self.enabled = enabled
            self.parallelizable = parallelizable
            self.target = target
            self.selectedTags = selectedTags
            self.skippedTags = skippedTags
        }
    }

    public let configurations: [Configuration]?
    public let defaultOptions: [String: AnyCodable]?
    public let testTargets: [TestTarget]
    public let version: Int?

    public init(
        testTargets: [TestTarget],
        configurations: [Configuration]? = nil,
        defaultOptions: [String: AnyCodable]? = nil,
        version: Int? = nil
    ) {
        self.configurations = configurations
        self.defaultOptions = defaultOptions
        self.testTargets = testTargets
        self.version = version
    }
}
