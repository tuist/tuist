import FileSystemTesting
import Foundation
import Path
import Testing
import TuistCore
import TuistSupport
import XcodeGraph
@testable import TuistGenerator

struct XcodeCacheSettingsProjectMapperTests {
    @Test(.inTemporaryDirectory) 
    func map_whenCachingDisabled_returnsUnmodifiedProject() async throws {
        // Given
        let tuist = Tuist.test(
            project: .test(
                generatedProject: .test(
                    generationOptions: .test(enableCaching: false)
                )
            ),
            fullHandle: "test-handle"
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
        let tuist = Tuist.test(
            project: .test(
                generatedProject: .test(
                    generationOptions: .test(enableCaching: true)
                )
            ),
            fullHandle: nil
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
        let tuist = Tuist.test(
            project: .test(
                generatedProject: .test(
                    generationOptions: .test(enableCaching: true)
                )
            ),
            fullHandle: fullHandle
        )
        let subject = XcodeCacheSettingsProjectMapper(tuist: tuist)
        let project = Project.test(
            name: "TestProject",
            settings: .test(
                base: ["EXISTING_SETTING": .string("value")],
                configurations: [.debug: nil, .release: nil],
                defaultSettings: .recommended
            )
        )
        
        // When
        let (mappedProject, sideEffects) = try subject.map(project: project)
        
        // Then
        #expect(sideEffects.isEmpty)
        #expect(mappedProject.name == project.name)
        
        let baseSettings = mappedProject.settings.base
        #expect(baseSettings["EXISTING_SETTING"] == .string("value"))
        #expect(baseSettings["COMPILATION_CACHE_ENABLE_CACHING"] == .string("YES"))
        #expect(baseSettings["COMPILATION_CACHE_ENABLE_PLUGIN"] == .string("YES"))
        
        let socketPath = Environment.current.socketPathString(for: fullHandle)
        #expect(baseSettings["COMPILATION_CACHE_REMOTE_SERVICE_PATH"] == .string(socketPath))
        
        // Verify configurations and defaultSettings are preserved
        #expect(mappedProject.settings.configurations == project.settings.configurations)
        #expect(mappedProject.settings.defaultSettings == project.settings.defaultSettings)
    }
    
    @Test(.inTemporaryDirectory) 
    func map_whenNoExistingSettings_addsOnlyCacheSettings() async throws {
        // Given
        let fullHandle = "org/project"
        let tuist = Tuist.test(
            project: .test(
                generatedProject: .test(
                    generationOptions: .test(enableCaching: true)
                )
            ),
            fullHandle: fullHandle
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
        #expect(baseSettings.count == 3)
        #expect(baseSettings["COMPILATION_CACHE_ENABLE_CACHING"] == .string("YES"))
        #expect(baseSettings["COMPILATION_CACHE_ENABLE_PLUGIN"] == .string("YES"))
        
        let socketPath = Environment.current.socketPathString(for: fullHandle)
        #expect(baseSettings["COMPILATION_CACHE_REMOTE_SERVICE_PATH"] == .string(socketPath))
    }
    
    @Test(.inTemporaryDirectory) 
    func map_preservesAllProjectProperties() async throws {
        // Given
        let fullHandle = "test/handle"
        let tuist = Tuist.test(
            project: .test(
                generatedProject: .test(
                    generationOptions: .test(enableCaching: true)
                )
            ),
            fullHandle: fullHandle
        )
        let subject = XcodeCacheSettingsProjectMapper(tuist: tuist)
        
        let targets = [
            "App": Target.test(name: "App", product: .app),
            "Framework": Target.test(name: "Framework", product: .framework),
        ]
        
        let project = Project.test(
            path: "/path/to/project",
            name: "ComplexProject",
            organizationName: "TestOrg",
            developmentRegion: "en",
            options: .test(automaticSchemesOptions: .enabled),
            settings: .test(
                base: ["CUSTOM": .string("value")],
                configurations: [
                    .debug: Configuration.test(name: "Debug"),
                    .release: Configuration.test(name: "Release"),
                ],
                defaultSettings: .essential
            ),
            targets: targets,
            packages: [.remote(url: "https://example.com/package", requirement: .exact("1.0.0"))],
            schemes: [Scheme.test(name: "AppScheme")],
            fileHeaderTemplate: .string("// Custom header"),
            additionalFiles: [FileElement.test(path: "/additional/file")],
            resourceSynthesizers: [ResourceSynthesizer.test()],
            lastUpgradeCheck: Version(13, 0, 0),
            isExternal: false
        )
        
        // When
        let (mappedProject, _) = try subject.map(project: project)
        
        // Then
        #expect(mappedProject.path == project.path)
        #expect(mappedProject.name == project.name)
        #expect(mappedProject.organizationName == project.organizationName)
        #expect(mappedProject.developmentRegion == project.developmentRegion)
        #expect(mappedProject.options == project.options)
        #expect(mappedProject.targets == project.targets)
        #expect(mappedProject.packages == project.packages)
        #expect(mappedProject.schemes == project.schemes)
        #expect(mappedProject.fileHeaderTemplate == project.fileHeaderTemplate)
        #expect(mappedProject.additionalFiles == project.additionalFiles)
        #expect(mappedProject.resourceSynthesizers == project.resourceSynthesizers)
        #expect(mappedProject.lastUpgradeCheck == project.lastUpgradeCheck)
        #expect(mappedProject.isExternal == project.isExternal)
        
        // Only settings should be modified
        #expect(mappedProject.settings != project.settings)
        #expect(mappedProject.settings.base["CUSTOM"] == .string("value"))
    }
    
    @Test(.inTemporaryDirectory) 
    func map_whenGeneratedProjectNil_returnsUnmodifiedProject() async throws {
        // Given
        let tuist = Tuist.test(
            project: .test(generatedProject: nil),
            fullHandle: "test-handle"
        )
        let subject = XcodeCacheSettingsProjectMapper(tuist: tuist)
        let project = Project.test(name: "TestProject")
        
        // When
        let (mappedProject, sideEffects) = try subject.map(project: project)
        
        // Then
        #expect(mappedProject == project)
        #expect(sideEffects.isEmpty)
    }
}