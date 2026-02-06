#if os(macOS)
    import FileSystem
    import FileSystemTesting
    import Foundation
    import Mockable
    import Path
    import ProjectDescription
    import Testing
    import TuistConfig
    import TuistConstants
    import TuistRootDirectoryLocator

    @testable import TuistConfigLoader
    @testable import TuistLoader

    struct SwiftConfigLoaderTests {
        private let rootDirectoryLocator: MockRootDirectoryLocating
        private let manifestLoader: MockManifestLoading
        private let fileSystem: FileSystem
        private var registeredConfigs: [AbsolutePath: Result<ProjectDescription.Config, Error>]

        init() {
            rootDirectoryLocator = .init()
            manifestLoader = .init()
            fileSystem = FileSystem()
            registeredConfigs = [:]
        }

        @Test(.inTemporaryDirectory)
        func loadConfig_defaultReturnedWhenPathDoesNotExist() async throws {
            let subject = makeSubject()
            let path: AbsolutePath = "/some/random/path"
            stubRootDirectory(nil)

            let result = try await subject.loadConfig(path: path)

            #expect(result == .default)
        }

        @Test(.inTemporaryDirectory)
        mutating func loadConfig_loadConfig_and_showsAWarning_when_usingConfigSwiftConvention() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let projectPath = temporaryDirectory.appending(component: "project")
            let configPath = projectPath.appending(components: "Tuist", "Config.swift")
            try await fileSystem.makeDirectory(at: configPath.parentDirectory)
            try await fileSystem.touch(configPath)
            stubConfig(.test(), at: configPath.parentDirectory)
            stubRootDirectory(projectPath)

            let subject = makeSubject()
            let result = try await subject.loadConfig(path: configPath)

            #expect(result == TuistConfig.Tuist(
                project: .generated(TuistGeneratedProjectOptions(
                    compatibleXcodeVersions: .all,
                    swiftVersion: nil,
                    plugins: [],
                    generationOptions: .test(),
                    installOptions: .test(),
                    cacheOptions: .test()
                )),
                fullHandle: nil,
                inspectOptions: .test(),
                url: Constants.URLs.production
            ))
        }

        @Test(.inTemporaryDirectory)
        mutating func loadConfig_loadConfig() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let projectPath = temporaryDirectory.appending(component: "project")
            let configPath = projectPath.appending(components: Constants.tuistManifestFileName)
            try await fileSystem.makeDirectory(at: configPath.parentDirectory)
            try await fileSystem.touch(configPath)
            stubConfig(.test(), at: configPath.parentDirectory)
            stubRootDirectory(projectPath)

            let subject = makeSubject()
            let result = try await subject.loadConfig(path: configPath)

            #expect(result == TuistConfig.Tuist(
                project: .generated(TuistGeneratedProjectOptions(
                    compatibleXcodeVersions: .all,
                    swiftVersion: nil,
                    plugins: [],
                    generationOptions: .test(),
                    installOptions: .test(),
                    cacheOptions: .test()
                )),
                fullHandle: nil,
                inspectOptions: .test(),
                url: Constants.URLs.production
            ))
        }

        @Test(.inTemporaryDirectory)
        mutating func loadConfig_loadConfigError() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let projectPath = temporaryDirectory.appending(component: "project")
            let configPath = projectPath.appending(components: Constants.tuistManifestFileName)
            try await fileSystem.makeDirectory(at: configPath.parentDirectory)
            try await fileSystem.touch(configPath)
            stubConfigError(TestError.testError, at: configPath.parentDirectory)
            stubRootDirectory(projectPath)

            let subject = makeSubject()
            await #expect(throws: TestError.testError) {
                try await subject.loadConfig(path: configPath)
            }
        }

        @Test(.inTemporaryDirectory)
        mutating func loadConfig_invalid_default_cache_profile_throws() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let projectPath = temporaryDirectory.appending(component: "project")
            let configPath = projectPath.appending(components: Constants.tuistManifestFileName)
            try await fileSystem.makeDirectory(at: configPath.parentDirectory)
            try await fileSystem.touch(configPath)
            let invalidProfiles = CacheProfiles.profiles(
                [
                    "development": .profile(.allPossible, and: ["tag:cacheable"]),
                ],
                default: "missing"
            )
            stubConfig(
                ProjectDescription.Config(project: .tuist(cacheOptions: .options(
                    keepSourceTargets: false,
                    profiles: invalidProfiles
                ))),
                at: configPath.parentDirectory
            )
            stubRootDirectory(projectPath)

            let subject = makeSubject()
            await #expect(
                throws: CacheOptionsManifestMapperError.defaultCacheProfileNotFound(
                    profile: "missing",
                    available: ["development"]
                )
            ) {
                try await subject.loadConfig(path: configPath)
            }
        }

        @Test(.inTemporaryDirectory)
        mutating func loadConfig_loadConfigInRootDirectory() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let projectPath = temporaryDirectory.appending(component: "project")
            let configPath = projectPath.appending(components: Constants.tuistManifestFileName)
            try await fileSystem.makeDirectory(at: configPath.parentDirectory)
            try await fileSystem.touch(configPath)
            stubRootDirectory(projectPath)
            let moduleAPath = projectPath.appending(components: "Module", "A")
            try await fileSystem.makeDirectory(at: moduleAPath)
            stubConfig(.test(), at: configPath.parentDirectory)

            let subject = makeSubject()
            let result = try await subject.loadConfig(path: moduleAPath)

            #expect(result == TuistConfig.Tuist(
                project: .generated(TuistGeneratedProjectOptions(
                    compatibleXcodeVersions: .all,
                    swiftVersion: nil,
                    plugins: [],
                    generationOptions: .test(),
                    installOptions: .test(),
                    cacheOptions: .test()
                )),
                fullHandle: nil,
                inspectOptions: .test(),
                url: Constants.URLs.production
            ))
        }

        @Test(.inTemporaryDirectory)
        mutating func loadConfig_with_full_handle_and_url() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let projectPath = temporaryDirectory.appending(component: "project")
            let configPath = projectPath.appending(components: Constants.tuistManifestFileName)
            try await fileSystem.makeDirectory(at: configPath.parentDirectory)
            try await fileSystem.touch(configPath)
            stubRootDirectory(projectPath)
            stubConfig(
                .test(
                    fullHandle: "tuist/tuist",
                    url: "https://test.tuist.io"
                ),
                at: configPath.parentDirectory
            )

            let subject = makeSubject()
            let result = try await subject.loadConfig(path: projectPath)

            let expectedURL = try #require(URL(string: "https://test.tuist.io"))
            #expect(result == TuistConfig.Tuist(
                project: .generated(TuistGeneratedProjectOptions(
                    compatibleXcodeVersions: .all,
                    swiftVersion: nil,
                    plugins: [],
                    generationOptions: .test(
                        buildInsightsDisabled: false,
                        testInsightsDisabled: false
                    ),
                    installOptions: .test(),
                    cacheOptions: .test()
                )),
                fullHandle: "tuist/tuist",
                inspectOptions: .test(),
                url: expectedURL
            ))
        }

        @Test(.inTemporaryDirectory)
        mutating func loadConfig_with_deprecated_cloud() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let projectPath = temporaryDirectory.appending(component: "project")
            let configPath = projectPath.appending(components: Constants.tuistManifestFileName)
            try await fileSystem.makeDirectory(at: configPath.parentDirectory)
            try await fileSystem.touch(configPath)
            stubRootDirectory(projectPath)
            stubConfig(
                ProjectDescription.Config(fullHandle: "tuist/tuist", url: "https://test.tuist.io", project: .tuist()),
                at: configPath.parentDirectory
            )

            let subject = makeSubject()
            let result = try await subject.loadConfig(path: projectPath)

            let expectedURL = try #require(URL(string: "https://test.tuist.io"))
            #expect(result == TuistConfig.Tuist(
                project: .generated(TuistGeneratedProjectOptions(
                    compatibleXcodeVersions: .all,
                    swiftVersion: nil,
                    plugins: [],
                    generationOptions: .test(
                        buildInsightsDisabled: false,
                        testInsightsDisabled: false
                    ),
                    installOptions: .test(),
                    cacheOptions: .test()
                )),
                fullHandle: "tuist/tuist",
                inspectOptions: .test(),
                url: expectedURL
            ))
        }

        @Test(.inTemporaryDirectory)
        func loadConfig_whenFileIsMissing_but_xcodeProjectIsPresent() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let projectPath = temporaryDirectory.appending(component: "project")
            try await fileSystem.makeDirectory(at: projectPath)
            try await fileSystem.touch(projectPath.appending(component: "Test.xcodeproj"))
            stubRootDirectory(nil)

            let subject = makeSubject()
            let result = try await subject.loadConfig(path: projectPath)

            #expect(result == TuistConfig.Tuist(
                project: .xcode(TuistXcodeProjectOptions()),
                fullHandle: nil,
                inspectOptions: .test(),
                url: Constants.URLs.production
            ))
        }

        @Test(.inTemporaryDirectory)
        func loadConfig_whenFileIsMissing_but_xcodeWorkspaceIsPresent() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let projectPath = temporaryDirectory.appending(component: "project")
            try await fileSystem.makeDirectory(at: projectPath)
            try await fileSystem.touch(projectPath.appending(component: "Test.xcworkspace"))
            stubRootDirectory(nil)

            let subject = makeSubject()
            let result = try await subject.loadConfig(path: projectPath)

            #expect(result == TuistConfig.Tuist(
                project: .xcode(TuistXcodeProjectOptions()),
                fullHandle: nil,
                inspectOptions: .test(),
                url: Constants.URLs.production
            ))
        }

        @Test(.inTemporaryDirectory)
        func loadConfig_whenFileIsMissing_but_swiftPackageExists() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let packageDirectoryPath = temporaryDirectory.appending(component: "package")
            try await fileSystem.makeDirectory(at: packageDirectoryPath)
            try await fileSystem.touch(packageDirectoryPath.appending(component: "Package.swift"))
            stubRootDirectory(nil)

            let subject = makeSubject()
            let result = try await subject.loadConfig(path: packageDirectoryPath)

            #expect(result == TuistConfig.Tuist(
                project: .swiftPackage(TuistSwiftPackageOptions()),
                fullHandle: nil,
                inspectOptions: .test(),
                url: Constants.URLs.production
            ))
        }

        @Test(.inTemporaryDirectory)
        func loadConfig_whenFileIsMissing_and_generatedWorkspaceExists() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let projectPath = temporaryDirectory.appending(component: "project")
            try await fileSystem.makeDirectory(at: projectPath)
            try await fileSystem.touch(projectPath.appending(component: "Workspace.swift"))
            try await fileSystem.touch(projectPath.appending(component: "Test.xcworkspace"))
            stubRootDirectory(nil)

            let subject = makeSubject()
            let result = try await subject.loadConfig(path: projectPath)

            #expect(result == TuistConfig.Tuist(
                project: .defaultGeneratedProject(),
                fullHandle: nil,
                inspectOptions: .test(),
                url: Constants.URLs.production
            ))
        }

        @Test(.inTemporaryDirectory)
        func loadConfig_whenFileIsMissing_and_generatedProjectExists() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let projectPath = temporaryDirectory.appending(component: "project")
            try await fileSystem.makeDirectory(at: projectPath)
            try await fileSystem.touch(projectPath.appending(component: "Project.swift"))
            try await fileSystem.touch(projectPath.appending(component: "Project.xcodeproj"))
            stubRootDirectory(nil)

            let subject = makeSubject()
            let result = try await subject.loadConfig(path: projectPath)

            #expect(result == TuistConfig.Tuist(
                project: .defaultGeneratedProject(),
                fullHandle: nil,
                inspectOptions: .test(),
                url: Constants.URLs.production
            ))
        }

        // MARK: - Helpers

        private func makeSubject() -> SwiftConfigLoader {
            given(manifestLoader)
                .loadConfig(at: .any)
                .willProduce { [registeredConfigs] path in
                    guard let config = registeredConfigs[path] else {
                        throw ManifestLoaderError.manifestNotFound(.config, path)
                    }
                    return try config.get()
                }
            return SwiftConfigLoader(
                manifestLoader: manifestLoader,
                rootDirectoryLocator: rootDirectoryLocator,
                fileSystem: fileSystem
            )
        }

        private mutating func stubConfigError(_ error: Error, at path: AbsolutePath) {
            registeredConfigs[path] = .failure(error)
        }

        private mutating func stubConfig(_ config: ProjectDescription.Config, at path: AbsolutePath) {
            registeredConfigs[path] = .success(config)
        }

        private func stubRootDirectory(_ path: AbsolutePath?) {
            given(rootDirectoryLocator)
                .locate(from: .any)
                .willReturn(path as AbsolutePath?)
        }

        private enum TestError: Error, Equatable {
            case testError
        }
    }
#endif
