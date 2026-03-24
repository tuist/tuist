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
    var projectMapperFactory: ProjectMapperFactory!
    var subject: WorkspaceMapperFactory!

    init() {
        projectMapperFactory = ProjectMapperFactory()
    }

    @Test func default_contains_the_project_workspace_mapper() {
        // Given
        subject = WorkspaceMapperFactory(
            projectMapper: SequentialProjectMapper(
                mappers: projectMapperFactory.default(
                    tuist: .default
                )
            )
        )

        // When
        let got = subject.default(tuist: .default)

        // Then
        #expect(got.contains(where: { $0 is ProjectWorkspaceMapper }))
    }

    @Test func default_contains_the_tuist_workspace_identifier_mapper() {
        // Given
        subject = WorkspaceMapperFactory(
            projectMapper: SequentialProjectMapper(
                mappers: projectMapperFactory.default(
                    tuist: .default
                )
            )
        )

        // When
        let got = subject.default(tuist: .default)

        // Then
        #expect(got.contains(where: { $0 is TuistWorkspaceIdentifierMapper }))
    }

    @Test func default_contains_the_tuist_workspace_render_markdown_readme_mapper() {
        // Given
        subject = WorkspaceMapperFactory(
            projectMapper: SequentialProjectMapper(
                mappers: projectMapperFactory.default(
                    tuist: .default
                )
            )
        )

        // When
        let got = subject.default(tuist: .default)

        // Then
        #expect(got.contains(where: { $0 is TuistWorkspaceRenderMarkdownReadmeMapper }))
    }

    @Test func default_contains_the_tide_template_macros_mapper() {
        // Given
        subject = WorkspaceMapperFactory(
            projectMapper: SequentialProjectMapper(
                mappers: projectMapperFactory.default(
                    tuist: .default
                )
            )
        )

        // When
        let got = subject.default(tuist: .default)

        // Then
        #expect(got.contains(where: { $0 is IDETemplateMacrosMapper }))
    }

    @Test func default_contains_the_last_upgrade_version_mapper() {
        // Given
        subject = WorkspaceMapperFactory(
            projectMapper: SequentialProjectMapper(
                mappers: projectMapperFactory.default(
                    tuist: .default
                )
            )
        )

        // When
        let got = subject.default(tuist: .default)

        // Then
        #expect(got.contains(where: { $0 is LastUpgradeVersionWorkspaceMapper }))
    }
}

#if canImport(TuistCacheEE)
    struct CacheWorkspaceMapperFactoryTests {
        var projectMapperFactory: ProjectMapperFactory!
        var subject: CacheWorkspaceMapperFactory!

        init() {
            projectMapperFactory = ProjectMapperFactory()
        }

        @Test func binaryCacheWarming_returns_default_mappers() throws {
            // Given
            subject =
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
