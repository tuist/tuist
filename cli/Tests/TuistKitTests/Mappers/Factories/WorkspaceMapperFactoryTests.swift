import Foundation
import Path
import Testing
import TSCUtility
import TuistLoader
import XcodeGraph
@testable import TuistAutomation
@testable import TuistCore
@testable import TuistGenerator
@testable import TuistKit
@testable import TuistTesting

#if canImport(TuistCacheEE)
    import TuistCacheEE
#endif

struct WorkspaceMapperFactoryTests {
    let projectMapperFactory: ProjectMapperFactory

    init() {
        projectMapperFactory = ProjectMapperFactory()
    }

    private func makeSubject() -> WorkspaceMapperFactory {
        WorkspaceMapperFactory(
            projectMapper: SequentialProjectMapper(
                mappers: projectMapperFactory.default(
                    tuist: .default
                )
            )
        )
    }

    @Test func default_contains_the_project_workspace_mapper() {
        // Given
        let subject = makeSubject()

        // When
        let got = subject.default(tuist: .default)

        // Then
        #expect(got.contains(where: { $0 is ProjectWorkspaceMapper }))
    }

    @Test func default_contains_the_tuist_workspace_identifier_mapper() {
        // Given
        let subject = makeSubject()

        // When
        let got = subject.default(tuist: .default)

        // Then
        #expect(got.contains(where: { $0 is TuistWorkspaceIdentifierMapper }))
    }

    @Test func default_contains_the_tuist_workspace_render_markdown_readme_mapper() {
        // Given
        let subject = makeSubject()

        // When
        let got = subject.default(tuist: .default)

        // Then
        #expect(got.contains(where: { $0 is TuistWorkspaceRenderMarkdownReadmeMapper }))
    }

    @Test func default_contains_the_tide_template_macros_mapper() {
        // Given
        let subject = makeSubject()

        // When
        let got = subject.default(tuist: .default)

        // Then
        #expect(got.contains(where: { $0 is IDETemplateMacrosMapper }))
    }

    @Test func default_contains_the_last_upgrade_version_mapper() {
        // Given
        let subject = makeSubject()

        // When
        let got = subject.default(tuist: .default)

        // Then
        #expect(got.contains(where: { $0 is LastUpgradeVersionWorkspaceMapper }))
    }
}

#if canImport(TuistCacheEE)
    struct CacheWorkspaceMapperFactoryTests {
        let projectMapperFactory: ProjectMapperFactory

        init() {
            projectMapperFactory = ProjectMapperFactory()
        }

        @Test func binaryCacheWarming_returns_default_mappers() throws {
            // Given
            let subject =
                CacheWorkspaceMapperFactory(
                    projectMapper: SequentialProjectMapper(
                        mappers: projectMapperFactory.default(tuist: .test())
                    )
                )

            // When
            let got = subject.binaryCacheWarming(tuist: .test())

            // Then
            #expect(got.contains(where: { $0 is ProjectWorkspaceMapper }))
        }
    }

#endif
