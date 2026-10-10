import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistCore
import TuistTesting
import XcodeGraph
@testable import TuistGenerator

struct CachedModulesDebuggingGraphMapperTests {
    private let subject = CachedModulesDebuggingGraphMapper()

    @Test(.inTemporaryDirectory)
    func map_configuresRunAndTestActionsThatUseCachedModules() async throws {
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let originalLLDBInitFile = projectPath.appending(components: "Debugger", "custom.lldbinit")
        let cachedFrameworkPath = projectPath.appending(
            components: ".tuist-cache", "hash", "Feature.xcframework"
        )
        let cachedUIFrameworkPath = projectPath.appending(
            components: ".tuist-cache", "ui-hash", "UIFeature.xcframework"
        )
        let app = Target.test(name: "App", product: .app)
        let tests = Target.test(name: "AppTests", product: .unitTests)
        let uiTests = Target.test(name: "AppUITests", product: .uiTests)
        let feature = Target.test(name: "Feature", product: .framework)
        let uiFeature = Target.test(name: "UIFeature", product: .framework)
        let scheme = Scheme.test(
            name: "App Scheme",
            buildAction: BuildAction(targets: [TargetReference(projectPath: projectPath, name: "App")]),
            testAction: TestAction.test(
                targets: [
                    TestableTarget(target: TargetReference(projectPath: projectPath, name: "AppTests")),
                    TestableTarget(target: TargetReference(projectPath: projectPath, name: "AppUITests")),
                ]
            ),
            runAction: RunAction.test(
                customLLDBInitFile: originalLLDBInitFile,
                executable: TargetReference(projectPath: projectPath, name: "App")
            )
        )
        let project = Project.test(
            path: projectPath,
            sourceRootPath: projectPath,
            targets: [app, tests, uiTests, feature, uiFeature],
            schemes: [scheme]
        )
        let cachedFramework = GraphDependency.testXCFramework(path: cachedFrameworkPath, linking: .dynamic)
        let cachedUIFramework = GraphDependency.testXCFramework(path: cachedUIFrameworkPath, linking: .dynamic)
        let workspace = Workspace.test(path: projectPath, projects: [projectPath], schemes: [scheme])
        let sourceGraph = Graph.test(
            workspace: workspace,
            projects: [projectPath: project],
            dependencies: [
                .target(name: "App", path: projectPath): [.target(name: "Feature", path: projectPath)],
                .target(name: "AppTests", path: projectPath): [.target(name: "Feature", path: projectPath)],
                .target(name: "AppUITests", path: projectPath): [.target(name: "UIFeature", path: projectPath)],
                .target(name: "Feature", path: projectPath): [],
                .target(name: "UIFeature", path: projectPath): [],
            ]
        )
        let cachedGraph = Graph.test(
            workspace: workspace,
            projects: [projectPath: project],
            dependencies: [
                .target(name: "App", path: projectPath): [cachedFramework],
                .target(name: "AppTests", path: projectPath): [cachedFramework],
                .target(name: "AppUITests", path: projectPath): [cachedUIFramework],
                cachedFramework: [],
                cachedUIFramework: [],
            ]
        )
        var environment = MapperEnvironment()
        environment.initialGraphWithSources = sourceGraph

        let (mappedGraph, sideEffects, _) = try await subject.map(
            graph: cachedGraph,
            environment: environment
        )

        let mappedScheme = try #require(mappedGraph.projects[projectPath]?.schemes.first)
        let runAction = try #require(mappedScheme.runAction)
        let testAction = try #require(mappedScheme.testAction)
        #expect(runAction.preActions.first?.title == "Update Tuist cache debugger settings")
        #expect(testAction.preActions.first?.title == "Update Tuist cache debugger settings")
        #expect(runAction.preActions.first?.target?.name == "App")
        #expect(testAction.preActions.first?.target?.name == "AppTests")
        #expect(runAction.customLLDBInitFile?.pathString.hasSuffix("-run.lldbinit") == true)
        #expect(testAction.customLLDBInitFile?.pathString.hasSuffix("-test.lldbinit") == true)
        #expect(mappedGraph.workspace.schemes.first?.runAction?.customLLDBInitFile != nil)
        #expect(mappedGraph.workspace.schemes.first?.testAction?.customLLDBInitFile != nil)

        let runFile = try #require(fileDescriptor(at: runAction.customLLDBInitFile, in: sideEffects))
        let runData = try #require(runFile.contents)
        let runContents = try #require(String(data: runData, encoding: .utf8))
        #expect(runContents.contains("command source -s 0 \"\(originalLLDBInitFile.pathString)\""))
        #expect(runContents.contains(cachedFrameworkPath.parentDirectory.pathString))
        #expect(runContents.contains("settings set symbols.use-swift-explicit-module-loader false"))

        let testFile = try #require(fileDescriptor(at: testAction.customLLDBInitFile, in: sideEffects))
        let testData = try #require(testFile.contents)
        let testContents = try #require(String(data: testData, encoding: .utf8))
        #expect(testContents.contains(cachedFrameworkPath.parentDirectory.pathString))
        #expect(testContents.contains(cachedUIFrameworkPath.parentDirectory.pathString))
        #expect(!testContents.contains("command source"))

        let script = try #require(runAction.preActions.first?.scriptText)
        #expect(script.contains("symbols.cas-path"))
        #expect(script.contains("symbols.cas-plugin-path"))
        #expect(script.contains("symbols.cas-plugin-options"))
        #expect(script.contains("target.swift-framework-search-paths"))
        #expect(script.contains("target.swift-module-search-paths"))
        #expect(script.contains("target.swift-extra-clang-flags"))
        #expect(script.contains("/^sdk"))
        #expect(script.contains("symbols.use-swift-explicit-module-loader false"))
    }

    @Test(.inTemporaryDirectory)
    func map_configuresTestActionsUsingCachedModulesFromTestPlans() async throws {
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let cachedFrameworkPath = projectPath.appending(
            components: ".tuist-cache", "hash", "Feature.xcframework"
        )
        let tests = Target.test(name: "AppTests", product: .unitTests)
        let feature = Target.test(name: "Feature", product: .framework)
        let testTarget = TestableTarget(target: TargetReference(projectPath: projectPath, name: "AppTests"))
        let scheme = Scheme.test(
            testAction: TestAction.test(
                targets: [],
                testPlans: [TestPlan(
                    path: projectPath.appending(component: "App.xctestplan"),
                    testTargets: [testTarget],
                    isDefault: true
                )]
            ),
            runAction: nil
        )
        let project = Project.test(path: projectPath, targets: [tests, feature], schemes: [scheme])
        let cachedFramework = GraphDependency.testXCFramework(path: cachedFrameworkPath, linking: .dynamic)
        let sourceGraph = Graph.test(
            projects: [projectPath: project],
            dependencies: [
                .target(name: "AppTests", path: projectPath): [.target(name: "Feature", path: projectPath)],
                .target(name: "Feature", path: projectPath): [],
            ]
        )
        let cachedGraph = Graph.test(
            projects: [projectPath: project],
            dependencies: [
                .target(name: "AppTests", path: projectPath): [cachedFramework],
                cachedFramework: [],
            ]
        )
        var environment = MapperEnvironment()
        environment.initialGraphWithSources = sourceGraph

        let (mappedGraph, sideEffects, _) = try await subject.map(graph: cachedGraph, environment: environment)

        let testAction = try #require(mappedGraph.projects[projectPath]?.schemes.first?.testAction)
        #expect(testAction.preActions.first?.title == "Update Tuist cache debugger settings")
        #expect(testAction.preActions.first?.target == testTarget.target)
        let testFile = try #require(fileDescriptor(at: testAction.customLLDBInitFile, in: sideEffects))
        let testData = try #require(testFile.contents)
        let testContents = try #require(String(data: testData, encoding: .utf8))
        #expect(testContents.contains(cachedFrameworkPath.parentDirectory.pathString))
    }

    @Test(.inTemporaryDirectory)
    func map_doesNotConfigureRunActionUsingCachedModulesFromALaterBuildTarget() async throws {
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let cachedFrameworkPath = projectPath.appending(
            components: ".tuist-cache", "hash", "Feature.xcframework"
        )
        let primaryApp = Target.test(name: "PrimaryApp", product: .app)
        let secondaryApp = Target.test(name: "SecondaryApp", product: .app)
        let feature = Target.test(name: "Feature", product: .framework)
        let scheme = Scheme.test(
            buildAction: BuildAction(targets: [
                TargetReference(projectPath: projectPath, name: "PrimaryApp"),
                TargetReference(projectPath: projectPath, name: "SecondaryApp"),
            ]),
            testAction: nil,
            runAction: RunAction.test(
                executable: nil,
                expandVariableFromTarget: TargetReference(projectPath: projectPath, name: "SecondaryApp")
            )
        )
        let project = Project.test(
            path: projectPath,
            targets: [primaryApp, secondaryApp, feature],
            schemes: [scheme]
        )
        let cachedFramework = GraphDependency.testXCFramework(path: cachedFrameworkPath, linking: .dynamic)
        let sourceGraph = Graph.test(
            projects: [projectPath: project],
            dependencies: [
                .target(name: "PrimaryApp", path: projectPath): [],
                .target(name: "SecondaryApp", path: projectPath): [.target(name: "Feature", path: projectPath)],
                .target(name: "Feature", path: projectPath): [],
            ]
        )
        let cachedGraph = Graph.test(
            projects: [projectPath: project],
            dependencies: [
                .target(name: "PrimaryApp", path: projectPath): [],
                .target(name: "SecondaryApp", path: projectPath): [cachedFramework],
                cachedFramework: [],
            ]
        )
        var environment = MapperEnvironment()
        environment.initialGraphWithSources = sourceGraph

        let (mappedGraph, sideEffects, _) = try await subject.map(graph: cachedGraph, environment: environment)

        #expect(mappedGraph.projects[projectPath]?.schemes.first?.runAction?.customLLDBInitFile == nil)
        #expect(sideEffects.isEmpty)
    }

    @Test(.inTemporaryDirectory)
    func map_doesNotConfigureActionsWhenDebuggerAttachmentIsDisabled() async throws {
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let cachedFrameworkPath = projectPath.appending(
            components: ".tuist-cache", "hash", "Feature.xcframework"
        )
        let app = Target.test(name: "App", product: .app)
        let tests = Target.test(name: "AppTests", product: .unitTests)
        let feature = Target.test(name: "Feature", product: .framework)
        let scheme = Scheme.test(
            buildAction: BuildAction(targets: [TargetReference(projectPath: projectPath, name: "App")]),
            testAction: TestAction.test(
                targets: [TestableTarget(target: TargetReference(projectPath: projectPath, name: "AppTests"))],
                attachDebugger: false
            ),
            runAction: RunAction.test(
                attachDebugger: false,
                executable: TargetReference(projectPath: projectPath, name: "App")
            )
        )
        let project = Project.test(path: projectPath, targets: [app, tests, feature], schemes: [scheme])
        let cachedFramework = GraphDependency.testXCFramework(path: cachedFrameworkPath, linking: .dynamic)
        let sourceGraph = Graph.test(
            projects: [projectPath: project],
            dependencies: [
                .target(name: "App", path: projectPath): [.target(name: "Feature", path: projectPath)],
                .target(name: "AppTests", path: projectPath): [.target(name: "Feature", path: projectPath)],
                .target(name: "Feature", path: projectPath): [],
            ]
        )
        let cachedGraph = Graph.test(
            projects: [projectPath: project],
            dependencies: [
                .target(name: "App", path: projectPath): [cachedFramework],
                .target(name: "AppTests", path: projectPath): [cachedFramework],
                cachedFramework: [],
            ]
        )
        var environment = MapperEnvironment()
        environment.initialGraphWithSources = sourceGraph

        let (mappedGraph, sideEffects, _) = try await subject.map(graph: cachedGraph, environment: environment)

        #expect(mappedGraph == cachedGraph)
        #expect(sideEffects.isEmpty)
    }

    @Test(.inTemporaryDirectory)
    func map_doesNotConfigureSchemesForPrecompiledDependenciesThatWereAlreadyInTheSourceGraph() async throws {
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let frameworkPath = projectPath.appending(components: "Frameworks", "Vendor.xcframework")
        let app = Target.test(name: "App", product: .app)
        let scheme = Scheme.test(
            buildAction: BuildAction(targets: [TargetReference(projectPath: projectPath, name: "App")]),
            testAction: nil,
            runAction: RunAction.test(executable: TargetReference(projectPath: projectPath, name: "App"))
        )
        let project = Project.test(path: projectPath, targets: [app], schemes: [scheme])
        let vendorFramework = GraphDependency.testXCFramework(path: frameworkPath, linking: .dynamic)
        let graph = Graph.test(
            projects: [projectPath: project],
            dependencies: [
                .target(name: "App", path: projectPath): [vendorFramework],
                vendorFramework: [],
            ]
        )
        var environment = MapperEnvironment()
        environment.initialGraphWithSources = graph

        let (mappedGraph, sideEffects, _) = try await subject.map(graph: graph, environment: environment)

        #expect(mappedGraph == graph)
        #expect(sideEffects.isEmpty)
    }

    @Test func map_doesNothingWithoutTheSourceGraph() async throws {
        let graph = Graph.test()

        let (mappedGraph, sideEffects, _) = try await subject.map(
            graph: graph,
            environment: MapperEnvironment()
        )

        #expect(mappedGraph == graph)
        #expect(sideEffects.isEmpty)
    }

    @Test(.inTemporaryDirectory)
    func map_configuresCompilationCachingWithoutReplacedModules() async throws {
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let graph = compilationCacheGraph(at: projectPath)
        let subject = CachedModulesDebuggingGraphMapper(compilationCachingEnabled: true)

        for sourceGraph in [nil, graph] {
            var environment = MapperEnvironment()
            environment.initialGraphWithSources = sourceGraph
            let (mapped, sideEffects, _) = try await subject.map(graph: graph, environment: environment)

            #expect(sideEffects.count == 4)
            let projectScheme = try #require(mapped.projects[projectPath]?.schemes.first)
            let workspaceScheme = try #require(mapped.workspace.schemes.first)
            for scheme in [projectScheme, workspaceScheme] {
                let runAction = try #require(scheme.runAction)
                let testAction = try #require(scheme.testAction)
                #expect(runAction.preActions.map(\.title) == ["Update Tuist cache debugger settings", "Existing run action"])
                #expect(testAction.preActions.map(\.title) == ["Update Tuist cache debugger settings", "Existing test action"])
                #expect(runAction.preActions.first?.target?.name == "App")
                #expect(testAction.preActions.first?.target?.name == "AppTests")
                #expect(runAction.postActions == graph.projects[projectPath]?.schemes.first?.runAction?.postActions)
                #expect(testAction.postActions == graph.projects[projectPath]?.schemes.first?.testAction?.postActions)
                for path in [runAction.customLLDBInitFile, testAction.customLLDBInitFile] {
                    let file = try #require(fileDescriptor(at: path, in: sideEffects))
                    let contents = try #require(file.contents.flatMap { String(data: $0, encoding: .utf8) })
                    #expect(contents.contains("command source"))
                    #expect(!contents.contains("symbols.use-swift-explicit-module-loader"))
                    #expect(!contents.contains("target.swift-framework-search-paths"))
                    #expect(!contents.contains("target.swift-module-search-paths"))
                }
            }
        }
    }

    @Test(.inTemporaryDirectory)
    func map_doesNotConfigureCompilationCachingWhenDebuggerAttachmentIsDisabled() async throws {
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let graph = compilationCacheGraph(at: projectPath, attachDebugger: false)
        let subject = CachedModulesDebuggingGraphMapper(compilationCachingEnabled: true)

        let (mapped, sideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        #expect(mapped == graph)
        #expect(sideEffects.isEmpty)
    }

    @Test(.inTemporaryDirectory)
    func map_configuresImplicitRunActionsWithoutChangingLaunchDefaults() async throws {
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let subject = CachedModulesDebuggingGraphMapper(compilationCachingEnabled: true)

        for product: Product in [.app, .commandLineTool] {
            let primary = Target.test(name: "Primary", product: product)
            let secondary = Target.test(name: "Secondary", product: .app)
            let primaryReference = TargetReference(projectPath: projectPath, name: primary.name)
            let scheme = Scheme(
                name: "CheckBuild",
                buildAction: BuildAction(targets: [
                    primaryReference,
                    TargetReference(projectPath: projectPath, name: secondary.name),
                ])
            )
            let project = Project.test(
                path: projectPath,
                sourceRootPath: projectPath,
                settings: .test(configurations: [.debug("Development"): nil, .release("Production"): nil]),
                targets: [primary, secondary],
                schemes: [scheme]
            )
            let graph = Graph.test(
                workspace: .test(path: projectPath, projects: [projectPath], schemes: [scheme]),
                projects: [projectPath: project],
                dependencies: [
                    .target(name: primary.name, path: projectPath): [],
                    .target(name: secondary.name, path: projectPath): [],
                ]
            )

            let (mapped, sideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

            #expect(sideEffects.count == 2)
            let projectScheme = try #require(mapped.projects[projectPath]?.schemes.first)
            let workspaceScheme = try #require(mapped.workspace.schemes.first)
            for mappedScheme in [projectScheme, workspaceScheme] {
                let runAction = try #require(mappedScheme.runAction)
                #expect(runAction.configurationName == "Development")
                #expect(runAction.attachDebugger)
                #expect(runAction.customLLDBInitFile != nil)
                #expect(runAction.preActions.first?.target == primaryReference)
                #expect(runAction.executable == nil)
                #expect(runAction.filePath == nil)
                #expect(runAction.arguments == nil)
                #expect(runAction.options == RunActionOptions())
                #expect(runAction.diagnosticsOptions == SchemeDiagnosticsOptions(
                    mainThreadCheckerEnabled: true,
                    performanceAntipatternCheckerEnabled: true
                ))
                #expect(runAction.metalOptions == nil)
                #expect(runAction.postActions.isEmpty)
                #expect(!runAction.askForAppToLaunch)
                #expect(runAction.launchStyle == .automatically)
                #expect(runAction.customWorkingDirectory == nil)
                #expect(!runAction.useCustomWorkingDirectory)
                #expect(mappedScheme.buildAction == scheme.buildAction)
            }
        }
    }

    @Test(.inTemporaryDirectory)
    func map_keepsImplicitNonRunnableAndExtensionActionsUnchanged() async throws {
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let subject = CachedModulesDebuggingGraphMapper(compilationCachingEnabled: true)

        for product: Product in [.framework, .appExtension, .messagesExtension, .extensionKitExtension] {
            let target = Target.test(name: "Target", product: product)
            let scheme = Scheme(
                name: target.name,
                buildAction: BuildAction(targets: [TargetReference(projectPath: projectPath, name: target.name)])
            )
            let project = Project.test(path: projectPath, sourceRootPath: projectPath, targets: [target], schemes: [scheme])
            let graph = Graph.test(
                workspace: .test(path: projectPath, projects: [projectPath], schemes: [scheme]),
                projects: [projectPath: project],
                dependencies: [.target(name: target.name, path: projectPath): []]
            )

            let (mapped, sideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

            #expect(mapped == graph)
            #expect(sideEffects.isEmpty)
        }
    }

    @Test(.inTemporaryDirectory)
    func map_doesNotChainGeneratedInitializersWhenAppliedAgain() async throws {
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let graph = compilationCacheGraph(at: projectPath)
        let subject = CachedModulesDebuggingGraphMapper(compilationCachingEnabled: true)
        let (mapped, _, environment) = try await subject.map(graph: graph, environment: MapperEnvironment())

        let (remapped, sideEffects, _) = try await subject.map(graph: mapped, environment: environment)

        #expect(remapped == mapped)
        #expect(sideEffects.isEmpty)
    }

    @Test(.inTemporaryDirectory)
    func generatedScript_reversesResolvedMappingsWithoutChangingTheModuleLoader() async throws {
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let graph = compilationCacheGraph(at: projectPath)
        let subject = CachedModulesDebuggingGraphMapper(compilationCachingEnabled: true)
        let (mapped, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())
        let runAction = try #require(mapped.projects[projectPath]?.schemes.first?.runAction)
        let script = try #require(runAction.preActions.first?.scriptText)
        let initPath = try #require(runAction.customLLDBInitFile)
        let scriptPath = projectPath.appending(component: "debugger.sh")
        try await FileSystem().writeText(script, at: scriptPath)

        let root = projectPath.pathString + #"/repo 'single' "double" \backslash $(touch ignored)"#
        let scratch = root + "/Tuist/.build"
        let custom = projectPath.pathString + "/Custom mapping with spaces"
        let sdk = try runProcess(
            "/usr/bin/xcrun",
            arguments: ["--sdk", "macosx", "--show-sdk-path"],
            environment: ["PATH": "/usr/bin:/bin"]
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        let toolchain = projectPath.pathString + "/Swift.xctoolchain"
        let developer = try runProcess("/usr/bin/xcode-select", arguments: ["-p"], environment: ["PATH": "/usr/bin:/bin"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var environment = [
            "PATH": "/usr/bin:/bin",
            "COMPILATION_CACHE_ENABLE_CACHING": "YES",
            "SWIFT_ENABLE_PREFIX_MAPPING": "YES",
            "CLANG_ENABLE_PREFIX_MAPPING": "YES",
            "SWIFT_ENABLE_PROJECT_PREFIX_MAPPING": "NO",
            "CLANG_ENABLE_PROJECT_PREFIX_MAPPING": "NO",
            "SWIFT_OTHER_PREFIX_MAPPINGS": [shellQuoted(root + "=/^root"), shellQuoted(scratch + "=/^spm")]
                .joined(separator: " "),
            "CLANG_OTHER_PREFIX_MAPPINGS": [shellQuoted(root + "=/^root"), shellQuoted(custom + "=/^custom")]
                .joined(separator: " "),
            "SDKROOT": sdk,
            "DT_TOOLCHAIN_DIR": toolchain,
            "TOOLCHAIN_DIR": "/Metal.xctoolchain",
            "DEVELOPER_DIR": developer,
            "PROJECT_DIR": projectPath.pathString,
            "PROJECT_TEMP_DIR": projectPath.appending(component: "intermediates").pathString,
            "BUILT_PRODUCTS_DIR": projectPath.appending(component: "products").pathString,
        ]

        _ = try runProcess("/bin/sh", arguments: [scriptPath.pathString], environment: environment, workingDirectory: projectPath)
        let contents = try String(contentsOf: URL(fileURLWithPath: initPath.pathString), encoding: .utf8)
        let sourceMap = try #require(contents.split(separator: "\n").first { $0.hasPrefix("settings append target.source-map ") })
        let parsed = try runProcess(
            "/usr/bin/python3",
            arguments: ["-c", "import json, shlex, sys; print(json.dumps(shlex.split(sys.argv[1])))", String(sourceMap)],
            environment: environment
        )
        let arguments = try JSONDecoder().decode([String].self, from: Data(parsed.utf8))
        #expect(arguments == [
            "settings", "append", "target.source-map",
            "/^root", root, "/^spm", scratch, "/^custom", custom,
            "/^sdk", sdk, "/^toolchain", toolchain, "/^xcode", developer,
        ])
        #expect(contents.hasPrefix("command source -s 0 "))
        #expect(!contents.contains("symbols.cas-"))
        #expect(!contents.contains("symbols.use-swift-explicit-module-loader"))
        #expect(!contents.contains("target.swift-framework-search-paths"))
        #expect(!contents.contains("target.swift-module-search-paths"))
        #expect(!contents.contains("target.swift-extra-clang-flags"))
        #expect(!FileManager.default.fileExists(atPath: projectPath.appending(component: "ignored").pathString))

        _ = try runProcess("/bin/sh", arguments: [scriptPath.pathString], environment: environment, workingDirectory: projectPath)
        #expect(try String(contentsOf: URL(fileURLWithPath: initPath.pathString), encoding: .utf8) == contents)

        environment["SWIFT_ENABLE_PROJECT_PREFIX_MAPPING"] = "YES"
        _ = try runProcess("/bin/sh", arguments: [scriptPath.pathString], environment: environment, workingDirectory: projectPath)
        let withProjectMappings = try String(contentsOf: URL(fileURLWithPath: initPath.pathString), encoding: .utf8)
        #expect(withProjectMappings.contains("\"/^src\" \"\(projectPath.pathString)\""))
        #expect(withProjectMappings.contains("\"/^derived\" \"\(projectPath.pathString)/intermediates\""))
        #expect(withProjectMappings.contains("\"/^built\" \"\(projectPath.pathString)/products\""))

        environment["COMPILATION_CACHE_ENABLE_CACHING"] = "NO"
        _ = try runProcess("/bin/sh", arguments: [scriptPath.pathString], environment: environment, workingDirectory: projectPath)
        let withoutCaching = try String(contentsOf: URL(fileURLWithPath: initPath.pathString), encoding: .utf8)
        #expect(withoutCaching.hasPrefix("command source -s 0 "))
        #expect(!withoutCaching.contains("target.source-map"))
    }

    @Test(.inTemporaryDirectory)
    func generatedScript_createsInitializerWithoutCustomInitOrCachedModules() async throws {
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let graph = compilationCacheGraph(at: projectPath, customLLDBInitFiles: false)
        let subject = CachedModulesDebuggingGraphMapper(compilationCachingEnabled: true)
        let (mapped, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())
        let scheme = try #require(mapped.projects[projectPath]?.schemes.first)
        let actions = [
            (script: scheme.runAction?.preActions.first?.scriptText, initPath: scheme.runAction?.customLLDBInitFile),
            (script: scheme.testAction?.preActions.first?.scriptText, initPath: scheme.testAction?.customLLDBInitFile),
        ]
        var environment = [
            "PATH": "/usr/bin:/bin",
            "COMPILATION_CACHE_ENABLE_CACHING": "YES",
            "SWIFT_ENABLE_PREFIX_MAPPING": "YES",
            "SWIFT_OTHER_PREFIX_MAPPINGS": shellQuoted(projectPath.pathString + "=/^root"),
        ]

        for (index, action) in actions.enumerated() {
            let script = try #require(action.script)
            let initPath = try #require(action.initPath)
            let scriptPath = projectPath.appending(component: "debugger-\(index).sh")
            try await FileSystem().writeText(script, at: scriptPath)
            environment["COMPILATION_CACHE_ENABLE_CACHING"] = "YES"
            _ = try runProcess(
                "/bin/sh",
                arguments: [scriptPath.pathString],
                environment: environment,
                workingDirectory: projectPath
            )
            let contents = try String(contentsOf: URL(fileURLWithPath: initPath.pathString), encoding: .utf8)
            #expect(contents.hasPrefix("settings append target.source-map \"/^root\" \"\(projectPath.pathString)\""))
            #expect(contents.split(separator: "\n").count == 1)

            environment["COMPILATION_CACHE_ENABLE_CACHING"] = "NO"
            _ = try runProcess(
                "/bin/sh",
                arguments: [scriptPath.pathString],
                environment: environment,
                workingDirectory: projectPath
            )
            #expect(try String(contentsOf: URL(fileURLWithPath: initPath.pathString), encoding: .utf8).isEmpty)
        }
    }

    private func compilationCacheGraph(
        at projectPath: AbsolutePath,
        attachDebugger: Bool = true,
        customLLDBInitFiles: Bool = true
    ) -> Graph {
        let app = Target.test(name: "App", product: .app)
        let tests = Target.test(name: "AppTests", product: .unitTests)
        let scheme = Scheme.test(
            name: "App",
            buildAction: BuildAction(targets: [TargetReference(projectPath: projectPath, name: "App")]),
            testAction: TestAction.test(
                targets: [TestableTarget(target: TargetReference(projectPath: projectPath, name: "AppTests"))],
                attachDebugger: attachDebugger,
                preActions: [ExecutionAction(
                    title: "Existing test action",
                    scriptText: "echo test",
                    target: nil,
                    shellPath: nil
                )],
                postActions: [ExecutionAction(
                    title: "Existing test cleanup",
                    scriptText: "echo cleanup",
                    target: nil,
                    shellPath: nil
                )],
                customLLDBInitFile: customLLDBInitFiles ? projectPath.appending(component: "custom test.lldbinit") : nil
            ),
            runAction: RunAction.test(
                attachDebugger: attachDebugger,
                customLLDBInitFile: customLLDBInitFiles ? projectPath.appending(component: "custom run.lldbinit") : nil,
                preActions: [ExecutionAction(title: "Existing run action", scriptText: "echo run", target: nil, shellPath: nil)],
                postActions: [ExecutionAction(
                    title: "Existing run cleanup",
                    scriptText: "echo cleanup",
                    target: nil,
                    shellPath: nil
                )],
                executable: TargetReference(projectPath: projectPath, name: "App")
            )
        )
        let project = Project.test(path: projectPath, sourceRootPath: projectPath, targets: [app, tests], schemes: [scheme])
        return Graph.test(
            workspace: Workspace.test(path: projectPath, projects: [projectPath], schemes: [scheme]),
            projects: [projectPath: project],
            dependencies: [
                .target(name: "App", path: projectPath): [],
                .target(name: "AppTests", path: projectPath): [],
            ]
        )
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private func runProcess(
        _ executable: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: AbsolutePath? = nil
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = workingDirectory.map { URL(fileURLWithPath: $0.pathString) }
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        #expect(process.terminationStatus == 0, Comment(rawValue: text + String(decoding: errorData, as: UTF8.self)))
        return text
    }

    private func fileDescriptor(
        at path: AbsolutePath?,
        in sideEffects: [SideEffectDescriptor]
    ) -> FileDescriptor? {
        sideEffects.compactMap { sideEffect in
            guard case let .file(file) = sideEffect, file.path == path else { return nil }
            return file
        }.first
    }
}
