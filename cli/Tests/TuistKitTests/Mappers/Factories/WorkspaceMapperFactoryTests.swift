import Foundation
import Path
import TSCUtility
import TuistLoader
import XcodeGraph
import XCTest
@testable import TuistAutomation
@testable import TuistCore
@testable import TuistGenerator
@testable import TuistKit
@testable import TuistTesting

#if canImport(TuistCacheEE)
    import TuistCacheEE
#endif

final class WorkspaceMapperFactoryTests: TuistUnitTestCase {
    var projectMapperFactory: ProjectMapperFactory!
    var subject: WorkspaceMapperFactory!

    override func setUp() {
        super.setUp()
        projectMapperFactory = ProjectMapperFactory()
    }

    override func tearDown() {
        projectMapperFactory = nil
        subject = nil
        super.tearDown()
    }

    func test_default_contains_the_project_workspace_mapper() {
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

    func test_default_contains_the_tuist_workspace_identifier_mapper() {
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

    func test_default_contains_the_tuist_workspace_render_markdown_readme_mapper() {
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

    func test_default_contains_the_tide_template_macros_mapper() {
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

    func test_default_contains_the_last_upgrade_version_mapper() {
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
    final class CacheWorkspaceMapperFactoryTests: TuistUnitTestCase {
        var projectMapperFactory: ProjectMapperFactory!
        var subject: CacheWorkspaceMapperFactory!

        override func setUp() {
            super.setUp()
            projectMapperFactory = ProjectMapperFactory()
        }

        override func tearDown() {
            projectMapperFactory = nil
            subject = nil
            super.tearDown()
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
