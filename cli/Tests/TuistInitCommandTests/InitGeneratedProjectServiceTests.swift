#if os(macOS)
    import FileSystemTesting
    import Foundation
    import Mockable
    import Testing
    import TuistConstants
    import TuistCore
    import TuistLoader
    import TuistScaffold
    import TuistSupport
    import TuistTesting

    @testable import TuistInitCommand

    struct InitGeneratedProjectServiceTests {
        private let subject: InitGeneratedProjectService
        private let templatesDirectoryLocator: MockTemplatesDirectoryLocating
        private let templateGenerator: MockTemplateGenerating
        private let templateLoader: MockTemplateLoading
        private let templateGitLoader: MockTemplateGitLoader
        init() {
            templatesDirectoryLocator = MockTemplatesDirectoryLocating()
            templateGenerator = MockTemplateGenerating()
            templateLoader = MockTemplateLoading()
            templateGitLoader = MockTemplateGitLoader()
            subject = InitGeneratedProjectService(
                templateLoader: templateLoader,
                templatesDirectoryLocator: templatesDirectoryLocator,
                templateGenerator: templateGenerator,
                templateGitLoader: templateGitLoader
            )
        }

        @Test(.inTemporaryDirectory)
        func init_default_when_no_template() async throws {
            // Given
            let defaultTemplatePath = try #require(FileSystem.temporaryTestDirectory).appending(component: "default")
            given(templatesDirectoryLocator)
                .templateDirectories(at: .any)
                .willReturn([defaultTemplatePath])

            let expectedAttributes: [String: Template.Attribute.Value] = [
                "name": .string("Name"),
                "platform": .string("macOS"),
                "tuist_version": .string(Constants.version),
                "class_name": .string("Name"),
                "bundle_identifier": .string("Name"),
            ]
            given(templateGenerator)
                .generate(
                    template: .any,
                    to: .any,
                    attributes: .any
                )
                .willReturn()
            given(templateLoader)
                .loadTemplate(at: .any, plugins: .any)
                .willReturn(.test())

            // When
            try await subject.testRun(name: "Name", platform: "macos")

            // Then
            verify(templateGenerator)
                .generate(
                    template: .any,
                    to: .any,
                    attributes: .value(expectedAttributes)
                )
                .called(1)
        }

        @Test(.inTemporaryDirectory)
        func init_default_platform() async throws {
            // Given
            let defaultTemplatePath = try #require(FileSystem.temporaryTestDirectory).appending(component: "default")
            given(templatesDirectoryLocator)
                .templateDirectories(at: .any)
                .willReturn([defaultTemplatePath])

            let expectedAttributes: [String: Template.Attribute.Value] = [
                "name": .string("Name"),
                "platform": .string("iOS"),
                "tuist_version": .string(Constants.version),
                "class_name": .string("Name"),
                "bundle_identifier": .string("Name"),
            ]
            given(templateGenerator)
                .generate(
                    template: .any,
                    to: .any,
                    attributes: .any
                )
                .willReturn()
            given(templateLoader)
                .loadTemplate(at: .any, plugins: .any)
                .willReturn(.test())

            // When
            try await subject.testRun(name: "Name")

            // Then
            verify(templateGenerator)
                .generate(
                    template: .any,
                    to: .any,
                    attributes: .value(expectedAttributes)
                )
                .called(1)
        }

        @Test(.inTemporaryDirectory)
        func init_default_with_unusual_name() async throws {
            // Given
            let defaultTemplatePath = try #require(FileSystem.temporaryTestDirectory).appending(component: "default")
            given(templatesDirectoryLocator)
                .templateDirectories(at: .any)
                .willReturn([defaultTemplatePath])

            let expectedAttributes: [String: TuistCore.Template.Attribute.Value] = [
                "name": .string("unusual name"),
                "platform": .string("iOS"),
                "tuist_version": .string(Constants.version),
                "class_name": .string("UnusualName"),
                "bundle_identifier": .string("unusual-name"),
            ]
            given(templateGenerator)
                .generate(
                    template: .any,
                    to: .any,
                    attributes: .any
                )
                .willReturn()
            given(templateLoader)
                .loadTemplate(at: .any, plugins: .any)
                .willReturn(.test())

            // When
            try await subject.testRun(name: "unusual name")

            // Then
            verify(templateGenerator)
                .generate(
                    template: .any,
                    to: .any,
                    attributes: .value(expectedAttributes)
                )
                .called(1)
        }
    }

    extension InitGeneratedProjectService {
        @Test
        func testRun(
            name: String? = nil,
            platform: String? = nil,
            path: String? = nil
        ) async throws {
            try await run(
                name: name,
                platform: platform,
                path: path
            )
        }
    }
#endif
