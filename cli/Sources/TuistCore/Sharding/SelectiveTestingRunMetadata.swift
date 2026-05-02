import Foundation

/// Metadata persisted next to .xctestproducts to describe how selective testing
/// affected the selected test run during the build-for-testing phase.
public struct SelectiveTestingRunMetadata: Codable {
    /// Targets selected for the run before selective testing pruned cached targets.
    public let selectedTargetNames: [String]

    /// Targets still runnable after selective testing pruned cached targets.
    public let runnableTargetNames: [String]

    public init(
        selectedTargetNames: [String] = [],
        runnableTargetNames: [String] = []
    ) {
        self.selectedTargetNames = selectedTargetNames
        self.runnableTargetNames = runnableTargetNames
    }

    public static let fileName = "selective-testing-run-metadata.json"
}
