import TuistCore
import XcodeGraph
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

final class TargetActionDisableShowEnvVarsProjectMapperTests: TuistUnitTestCase {
    func test_map_environmentLoggingDisables() throws {
        // Given
        let subject = TargetActionDisableShowEnvVarsProjectMapper()
        let scriptA = TargetScript(name: "Pre Script", order: .pre)
        let scriptB = TargetScript(name: "Post Script", order: .post)
        let targetA = Target.test(name: "A", scripts: [scriptA, scriptB])
        let targetB = Target.test(name: "B", scripts: [scriptA, scriptB])
        let project = Project.test(options: .test(disableShowEnvironmentVarsInScriptPhases: true), targets: [targetA, targetB])

        // When
        let (updatedProject, _) = try subject.map(project: project)
        let updatedTargets = updatedProject.targets.values.sorted()

        // Then
        XCTAssertFalse(updatedTargets[1].scripts[0].showEnvVarsInLog)
        XCTAssertFalse(updatedTargets[1].scripts[1].showEnvVarsInLog)
        XCTAssertFalse(updatedTargets[0].scripts[0].showEnvVarsInLog)
        XCTAssertFalse(updatedTargets[0].scripts[1].showEnvVarsInLog)
        XCTAssertFalse(updatedTargets[1].scripts[0].showEnvVarsInLog)
        XCTAssertFalse(updatedTargets[1].scripts[1].showEnvVarsInLog)
        XCTAssertFalse(updatedTargets[0].scripts[0].showEnvVarsInLog)
        XCTAssertFalse(updatedTargets[0].scripts[1].showEnvVarsInLog)
    }

    func test_map_environmentLoggingEnables() throws {
        // Given
        let subject = TargetActionDisableShowEnvVarsProjectMapper()
        let scriptA = TargetScript(name: "Pre Script", order: .pre)
        let scriptB = TargetScript(name: "Post Script", order: .post)
        let targetA = Target.test(name: "A", scripts: [scriptA, scriptB])
        let targetB = Target.test(name: "B", scripts: [scriptA, scriptB])
        let project = Project.test(options: .test(disableShowEnvironmentVarsInScriptPhases: false), targets: [targetA, targetB])

        // When
        let (updatedProject, _) = try subject.map(project: project)
        let updatedTargets = updatedProject.targets.values.sorted()

        // Then
        XCTAssertTrue(updatedTargets[0].scripts[0].showEnvVarsInLog)
        XCTAssertTrue(updatedTargets[0].scripts[1].showEnvVarsInLog)
        XCTAssertTrue(updatedTargets[1].scripts[0].showEnvVarsInLog)
        XCTAssertTrue(updatedTargets[1].scripts[1].showEnvVarsInLog)
        XCTAssertTrue(updatedTargets[0].scripts[0].showEnvVarsInLog)
        XCTAssertTrue(updatedTargets[0].scripts[1].showEnvVarsInLog)
        XCTAssertTrue(updatedTargets[1].scripts[0].showEnvVarsInLog)
        XCTAssertTrue(updatedTargets[1].scripts[1].showEnvVarsInLog)
    }
}
