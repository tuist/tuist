import Foundation
import Path
import TSCUtility
import TuistLoader
import XcodeGraph
import Testing
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

    @Test func test_default_contains_the_project_workspace_mapper() {
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
        XCTAssertContainsElementOfType(got, ProjectWorkspaceMapper.self)
    }

    @Test func test_default_contains_the_tuist_workspace_identifier_mapper() {
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
        XCTAssertContainsElementOfType(got, TuistWorkspaceIdentifierMapper.self)
    }

    @Test func test_default_contains_the_tuist_workspace_render_markdown_readme_mapper() {
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
        XCTAssertContainsElementOfType(got, TuistWorkspaceRenderMarkdownReadmeMapper.self)
    }

    @Test func test_default_contains_the_tide_template_macros_mapper() {
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
        XCTAssertContainsElementOfType(got, IDETemplateMacrosMapper.self)
    }

    @Test func test_default_contains_the_last_upgrade_version_mapper() {
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
        XCTAssertContainsElementOfType(got, LastUpgradeVersionWorkspaceMapper.self)
    }
}

#if canImport(TuistCacheEE)
    struct CacheWorkspaceMapperFactoryTests {
        var projectMapperFactory: ProjectMapperFactory!
        var subject: CacheWorkspaceMapperFactory!

        init() {
            super.setUp()
            projectMapperFactory = ProjectMapperFactory()
        }

        func test_binaryCacheWarming_returns_default_mappers() throws {
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
            XCTAssertContainsElementOfType(got, ProjectWorkspaceMapper.self)
        }
    }

#endif
