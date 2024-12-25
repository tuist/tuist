/// This struct represent the configuration for workflows.
/// Every workflow is represented by a Swift file under the Workflows/ directory
/// relative to the Tuist directory containing Workflows.swift, and is modelled as an
/// executable.
public struct Workflows: Codable, Equatable, Sendable {
    public init() {
        dumpIfNeeded(self)
    }
}
