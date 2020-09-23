import TuistCore
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

public final class ConfigShowEnvironmentMapperTests: TuistUnitTestCase {
    func test_map_environmentLoggingDisables() throws {
        // Given
        let targetMapper = TargetActionEnvironmentMapper(false)

        let subject = TargetProjectMapper(mapper: targetMapper)
        let scriptA = TargetAction(name: "Pre Script", order: .pre)
        let scriptB = TargetAction(name: "Post Script", order: .post)
        let targetA = Target.test(name: "A", actions: [scriptA, scriptB])
        let targetB = Target.test(name: "B", actions: [scriptA, scriptB])
        let project = Project.test(targets: [targetA, targetB])

        // When
        let (updatedProject, _) = try subject.map(project: project)

        // Then
        XCTAssertTrue(project.targets[0].actions[0].showEnvVarsInLog)
        XCTAssertTrue(project.targets[0].actions[1].showEnvVarsInLog)
        XCTAssertTrue(project.targets[1].actions[0].showEnvVarsInLog)
        XCTAssertTrue(project.targets[1].actions[1].showEnvVarsInLog)
        XCTAssertFalse(updatedProject.targets[0].actions[0].showEnvVarsInLog)
        XCTAssertFalse(updatedProject.targets[0].actions[1].showEnvVarsInLog)
        XCTAssertFalse(updatedProject.targets[1].actions[0].showEnvVarsInLog)
        XCTAssertFalse(updatedProject.targets[1].actions[1].showEnvVarsInLog)
    }

    func test_map_environmentLoggingEnables() throws {
        // Given
        let targetMapper = TargetActionEnvironmentMapper(true)

        let subject = TargetProjectMapper(mapper: targetMapper)
        let scriptA = TargetAction(name: "Pre Script", order: .pre)
        let scriptB = TargetAction(name: "Post Script", order: .post)
        let targetA = Target.test(name: "A", actions: [scriptA, scriptB])
        let targetB = Target.test(name: "B", actions: [scriptA, scriptB])
        let project = Project.test(targets: [targetA, targetB])

        // When
        let (updatedProject, _) = try subject.map(project: project)

        // Then
        XCTAssertTrue(project.targets[0].actions[0].showEnvVarsInLog)
        XCTAssertTrue(project.targets[0].actions[1].showEnvVarsInLog)
        XCTAssertTrue(project.targets[1].actions[0].showEnvVarsInLog)
        XCTAssertTrue(project.targets[1].actions[1].showEnvVarsInLog)
        XCTAssertTrue(updatedProject.targets[0].actions[0].showEnvVarsInLog)
        XCTAssertTrue(updatedProject.targets[0].actions[1].showEnvVarsInLog)
        XCTAssertTrue(updatedProject.targets[1].actions[0].showEnvVarsInLog)
        XCTAssertTrue(updatedProject.targets[1].actions[1].showEnvVarsInLog)
    }
}
