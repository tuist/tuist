import Foundation
import Path
import TestCoverageAttribution
import Testing

@testable import XcodeGraph

@Suite(.coverageAttribution)
struct BuildActionBuildForTests {
    @Test func codableWithBuildForOptions() throws {
        let target = TargetReference(
            projectPath: try AbsolutePath(validating: "/path/to/project"),
            name: "name"
        )
        let subject = BuildAction(
            targets: [target],
            buildFor: [target: [.running, .testing]]
        )

        let encoded = try JSONEncoder().encode(subject)
        let decoded = try JSONDecoder().decode(BuildAction.self, from: encoded)

        #expect(decoded == subject)
    }
}
