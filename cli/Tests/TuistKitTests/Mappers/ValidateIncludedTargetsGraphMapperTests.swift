import Path
import Testing
import TuistCore
import XcodeGraph
@testable import TuistKit
@testable import TuistTesting

struct ValidateIncludedTargetsGraphMapperTests {
    @Test func map_throws_when_an_included_target_is_not_in_the_graph() async throws {
        // Given
        let path = try AbsolutePath(validating: "/Project")
        let project = Project.test(path: path, targets: [Target.test(name: "App")])
        let graph = Graph.test(projects: [path: project])
        let subject = ValidateIncludedTargetsGraphMapper(includedTargets: [.named("Typo")])

        // When / Then
        await #expect(throws: FocusTargetsGraphMappersError.targetsNotFound(["Typo"])) {
            try await subject.map(graph: graph, environment: MapperEnvironment())
        }
    }

    @Test func map_throws_when_no_target_matches_the_included_queries() async throws {
        // Given
        let path = try AbsolutePath(validating: "/Project")
        let project = Project.test(path: path, targets: [Target.test(name: "App")])
        let graph = Graph.test(projects: [path: project])
        let subject = ValidateIncludedTargetsGraphMapper(includedTargets: [.tagged("unused-tag")])

        // When / Then
        await #expect(throws: FocusTargetsGraphMappersError.noTargetsFound) {
            try await subject.map(graph: graph, environment: MapperEnvironment())
        }
    }

    @Test func map_returns_the_graph_untouched_when_every_included_target_matches() async throws {
        // Given
        let path = try AbsolutePath(validating: "/Project")
        let project = Project.test(path: path, targets: [Target.test(name: "App"), Target.test(name: "Framework")])
        let graph = Graph.test(name: "input", projects: [path: project])
        let subject = ValidateIncludedTargetsGraphMapper(includedTargets: [.named("App")])

        // When
        let (got, sideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        #expect(got == graph)
        #expect(sideEffects.isEmpty)
    }

    @Test func map_returns_the_graph_untouched_when_no_targets_are_included() async throws {
        // Given
        let path = try AbsolutePath(validating: "/Project")
        let project = Project.test(path: path, targets: [Target.test(name: "App")])
        let graph = Graph.test(name: "input", projects: [path: project])
        let subject = ValidateIncludedTargetsGraphMapper(includedTargets: [])

        // When
        let (got, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        #expect(got == graph)
    }
}
