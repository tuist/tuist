import Foundation
import Path
import XcodeGraph
@testable import XcodeProj

extension XCScheme.TestableReference {
    static func test(
        skipped: Bool,
        parallelization: XCScheme.TestParallelization = .none,
        randomExecutionOrdering: Bool = false,
        buildableReference: XCScheme.BuildableReference,
        locationScenarioReference: XCScheme.LocationScenarioReference? = nil,
        skippedTests: [XCScheme.TestItem] = [],
        selectedTests: [XCScheme.TestItem] = [],
        useTestSelectionWhitelist: Bool? = nil
    ) -> XCScheme.TestableReference {
        XCScheme.TestableReference(
            skipped: skipped,
            parallelization: parallelization,
            randomExecutionOrdering: randomExecutionOrdering,
            buildableReference: buildableReference,
            locationScenarioReference: locationScenarioReference,
            skippedTests: skippedTests,
            selectedTests: selectedTests,
            useTestSelectionWhitelist: useTestSelectionWhitelist
        )
    }
}
