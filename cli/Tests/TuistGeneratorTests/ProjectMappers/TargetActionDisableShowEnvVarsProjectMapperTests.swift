import TuistCore
import XcodeGraph
import Testing
@testable import TuistGenerator
@testable import TuistTesting

struct TargetActionDisableShowEnvVarsProjectMapperTests {
    @Test
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
        #expect(!updatedTargets[1].scripts[0].showEnvVarsInLog)
        #expect(!updatedTargets[1].scripts[1].showEnvVarsInLog)
        #expect(!updatedTargets[0].scripts[0].showEnvVarsInLog)
        #expect(!updatedTargets[0].scripts[1].showEnvVarsInLog)
        #expect(!updatedTargets[1].scripts[0].showEnvVarsInLog)
        #expect(!updatedTargets[1].scripts[1].showEnvVarsInLog)
        #expect(!updatedTargets[0].scripts[0].showEnvVarsInLog)
        #expect(!updatedTargets[0].scripts[1].showEnvVarsInLog)
    }

    @Test
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
        #expect(updatedTargets[0].scripts[0].showEnvVarsInLog)
        #expect(updatedTargets[0].scripts[1].showEnvVarsInLog)
        #expect(updatedTargets[1].scripts[0].showEnvVarsInLog)
        #expect(updatedTargets[1].scripts[1].showEnvVarsInLog)
        #expect(updatedTargets[0].scripts[0].showEnvVarsInLog)
        #expect(updatedTargets[0].scripts[1].showEnvVarsInLog)
        #expect(updatedTargets[1].scripts[0].showEnvVarsInLog)
        #expect(updatedTargets[1].scripts[1].showEnvVarsInLog)
    }
}
