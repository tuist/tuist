import FileSystemTesting
import Foundation
import Path
import Testing
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
@testable import TuistGenerator

struct XcodeCacheSettingsProjectMapperTests {
    @Test(.inTemporaryDirectory)
    func map_whenCachingDisabled_returnsUnmodifiedProject() async throws {
        // Given
        let tuist = Tuist(
            project: .generated(
                .test(
                    generationOptions: .test(enableCaching: false)
                )
            ),
            fullHandle: "test/handle",
            inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
            url: Constants.URLs.production
        )
        let subject = XcodeCacheSettingsProjectMapper(tuist: tuist)
        let project = Project.test(
            name: "TestProject",
            settings: .test(
                base: ["EXISTING_SETTING": .string("value")],
                configurations: [.debug: nil, .release: nil]
            )
        )

        // When
        let (mappedProject, sideEffects) = try subject.map(project: project)

        // Then
        #expect(mappedProject == project)
        #expect(sideEffects.isEmpty)
    }

    @Test(.inTemporaryDirectory)
    func map_whenFullHandleNil_returnsUnmodifiedProject() async throws {
        // Given
        let tuist = Tuist(
            project: .generated(
                .test(
                    generationOptions: .test(enableCaching: true)
                )
            ),
            fullHandle: nil,
            inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
            url: Constants.URLs.production
        )
        let subject = XcodeCacheSettingsProjectMapper(tuist: tuist)
        let project = Project.test(
            name: "TestProject",
            settings: .test(
                base: ["EXISTING_SETTING": .string("value")]
            )
        )

        // When
        let (mappedProject, sideEffects) = try subject.map(project: project)

        // Then
        #expect(mappedProject == project)
        #expect(sideEffects.isEmpty)
    }

    @Test(.inTemporaryDirectory)
    func map_whenCachingEnabled_addsCacheSettings() async throws {
        // Given
        let fullHandle = "test-org/test-project"
        let tuist = Tuist(
            project: .generated(
                .test(
                    generationOptions: .test(enableCaching: true)
                )
            ),
            fullHandle: fullHandle,
            inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
            url: Constants.URLs.production
        )
        let subject = XcodeCacheSettingsProjectMapper(tuist: tuist)
        let project = Project.test(
            name: "TestProject",
            settings: .test(
                base: ["EXISTING_SETTING": .string("value")],
                configurations: [.debug: nil, .release: nil]
            )
        )

        // When
        let (mappedProject, sideEffects) = try subject.map(project: project)

        // Then
        #expect(sideEffects.isEmpty)

        let baseSettings = mappedProject.settings.base
        #expect(baseSettings["EXISTING_SETTING"] == .string("value"))
        #expect(baseSettings["COMPILATION_CACHE_ENABLE_CACHING"] == .string("YES"))
        #expect(baseSettings["COMPILATION_CACHE_ENABLE_PLUGIN"] == .string("YES"))
        #expect(baseSettings["COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS"] == .string("YES"))

        let socketPath = Environment.current.cacheSocketPathString(for: fullHandle)
        #expect(baseSettings["COMPILATION_CACHE_REMOTE_SERVICE_PATH"] == .string(socketPath))

        #expect(mappedProject.settings.configurations == project.settings.configurations)
    }

    @Test(.inTemporaryDirectory)
    func map_whenNoExistingSettings_addsOnlyCacheSettings() async throws {
        // Given
        let fullHandle = "org/project"
        let tuist = Tuist(
            project: .generated(
                .test(
                    generationOptions: .test(enableCaching: true)
                )
            ),
            fullHandle: fullHandle,
            inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
            url: Constants.URLs.production
        )
        let subject = XcodeCacheSettingsProjectMapper(tuist: tuist)
        let project = Project.test(
            name: "TestProject",
            settings: .test(base: [:])
        )

        // When
        let (mappedProject, sideEffects) = try subject.map(project: project)

        // Then
        #expect(sideEffects.isEmpty)

        let baseSettings = mappedProject.settings.base
        #expect(baseSettings["COMPILATION_CACHE_ENABLE_CACHING"] == .string("YES"))
        #expect(baseSettings["COMPILATION_CACHE_ENABLE_PLUGIN"] == .string("YES"))

        let socketPath = Environment.current.cacheSocketPathString(for: fullHandle)
        #expect(baseSettings["COMPILATION_CACHE_REMOTE_SERVICE_PATH"] == .string(socketPath))
    }

    @Test(.inTemporaryDirectory)
    func map_preservesOtherProjectProperties() async throws {
        // Given
        let fullHandle = "test/handle"
        let tuist = Tuist(
            project: .generated(
                .test(
                    generationOptions: .test(enableCaching: true)
                )
            ),
            fullHandle: fullHandle,
            inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
            url: Constants.URLs.production
        )
        let subject = XcodeCacheSettingsProjectMapper(tuist: tuist)

        let targets = [
            Target.test(name: "App", product: .app),
            Target.test(name: "Framework", product: .framework),
        ]

        let project = Project.test(
            path: "/path/to/project",
            name: "ComplexProject",
            settings: .test(
                base: ["CUSTOM": .string("value")],
                configurations: [
                    .debug: Configuration.test(),
                    .release: Configuration.test(),
                ]
            ),
            targets: targets
        )

        // When
        let (mappedProject, _) = try subject.map(project: project)

        // Then
        #expect(mappedProject.settings.base["CUSTOM"] == .string("value"))
        #expect(mappedProject.settings.base["COMPILATION_CACHE_ENABLE_CACHING"] == .string("YES"))
    }
}
