import Foundation
import Path
import Testing
import TuistCore
import XcodeGraph

@testable import TuistKit

@Suite
struct CacheIndexStoreGraphMapperTests {
    private let subject = CacheIndexStoreGraphMapper()

    @Test func appends_hermetic_prefix_map_flags_preserving_existing_flags() async throws {
        // Given
        let sourceRoot = try AbsolutePath(validating: "/checkout")
        let target = Target.test(
            name: "A",
            product: .framework,
            settings: .test(base: [
                "OTHER_SWIFT_FLAGS": .array(["-warnings-as-errors"]),
            ])
        )
        let project = Project.test(path: sourceRoot, targets: [target])
        let graph = Graph.test(
            path: sourceRoot,
            projects: [sourceRoot: project]
        )

        // When
        let (mapped, sideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        #expect(sideEffects.isEmpty)
        let mappedTarget = try #require(mapped.projects[sourceRoot]?.targets["A"])
        let swiftFlags = mappedTarget.settings?.base["OTHER_SWIFT_FLAGS"]
        let cFlags = mappedTarget.settings?.base["OTHER_C_FLAGS"]

        // The target's own flag survives, and the hermetic index flags are appended.
        #expect(swiftFlags == .array([
            "-warnings-as-errors",
            "-file-prefix-map", "/checkout=\(CacheIndexStore.sourceRootToken)",
            "-index-ignore-system-modules",
        ]))
        #expect(cFlags == .array([
            "-ffile-prefix-map=/checkout=\(CacheIndexStore.sourceRootToken)",
        ]))
    }

    @Test func adds_flags_to_targets_without_existing_settings() async throws {
        // Given
        let sourceRoot = try AbsolutePath(validating: "/checkout")
        let target = Target.test(name: "A", product: .framework, settings: nil)
        let project = Project.test(path: sourceRoot, targets: [target])
        let graph = Graph.test(path: sourceRoot, projects: [sourceRoot: project])

        // When
        let (mapped, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let mappedTarget = try #require(mapped.projects[sourceRoot]?.targets["A"])
        #expect(mappedTarget.settings?.base["OTHER_SWIFT_FLAGS"] == .array([
            "-file-prefix-map", "/checkout=\(CacheIndexStore.sourceRootToken)",
            "-index-ignore-system-modules",
        ]))
    }
}
