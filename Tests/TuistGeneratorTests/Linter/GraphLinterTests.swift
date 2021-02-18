import Foundation
import TSCBasic
import struct TSCUtility.Version
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistCoreTesting
@testable import TuistGenerator
@testable import TuistGraphTesting
@testable import TuistSupportTesting

final class GraphLinterTests: TuistUnitTestCase {
    var subject: GraphLinter!
    var graphTraverser: MockGraphTraverser!

    override func setUp() {
        super.setUp()
        graphTraverser = MockGraphTraverser()
        subject = GraphLinter(projectLinter: MockProjectLinter(),
                              staticProductsLinter: MockStaticProductsGraphLinter())
    }

    override func tearDown() {
        subject = nil
        graphTraverser = nil
        super.tearDown()
    }

    func test_lint_when_frameworks_are_missing() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let frameworkAPath = temporaryPath.appending(RelativePath("Carthage/Build/iOS/A.framework"))
        let frameworkBPath = temporaryPath.appending(RelativePath("Carthage/Build/iOS/B.framework"))
        try FileHandler.shared.createFolder(frameworkAPath)
        let graph = ValueGraph.test(dependencies: [
            ValueGraphDependency.testFramework(path: frameworkAPath): Set(),
            ValueGraphDependency.testFramework(path: frameworkBPath): Set(),
        ])
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertTrue(result.contains(LintingIssue(reason: "Framework not found at path \(frameworkBPath.pathString)", severity: .error)))
    }

    func test_lint_when_packages_and_xcode_10() throws {
        // Given
        let path: AbsolutePath = "/project"
        let package = Package.remote(url: "remote", requirement: .branch("master"))
        let versionStub = Version(10, 0, 0)
        xcodeController.selectedVersionStub = .success(versionStub)
        let graph = ValueGraph.test(packages: [path: ["package": package]])
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser)

        // Then
        let reason = "The project contains package dependencies but the selected version of Xcode is not compatible. Need at least 11 but got \(versionStub)"
        XCTAssertTrue(result.contains(LintingIssue(reason: reason, severity: .error)))
    }

    func test_lint_when_packages_and_xcode_11() throws {
        // Given
        let path: AbsolutePath = "/project"
        let package = Package.remote(url: "remote", requirement: .branch("master"))
        let versionStub = Version(11, 0, 0)
        xcodeController.selectedVersionStub = .success(versionStub)
        let graph = ValueGraph.test(packages: [path: ["package": package]])
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser)

        // Then
        let reason = "The project contains package dependencies but the selected version of Xcode is not compatible. Need at least 11 but got \(versionStub)"
        XCTAssertFalse(result.contains(LintingIssue(reason: reason, severity: .error)))
    }

    func test_lint_when_no_version_available() throws {
        // Given
        let path: AbsolutePath = "/project"
        let package = Package.remote(url: "remote", requirement: .branch("master"))
        let error = NSError.test()
        xcodeController.selectedVersionStub = .failure(error)
        let graph = ValueGraph.test(packages: [path: ["package": package]])
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertTrue(result.contains(LintingIssue(reason: "Could not determine Xcode version", severity: .error)))
    }

    func test_lint_when_staticFramework_depends_on_static_products() throws {
        // Given
        let path: AbsolutePath = "/project"
        let appTarget = Target.test(name: "AppTarget", product: .app)
        let staticFrameworkA = Target.test(name: "staticFrameworkA", product: .staticFramework)
        let staticFrameworkB = Target.test(name: "staticFrameworkB", product: .staticFramework)
        let staticLibrary = Target.test(name: "staticLibrary", product: .staticLibrary)

        let app = Project.test(path: "/tmp/app", name: "App", targets: [appTarget])
        let project = Project.test(path: path,
                                   name: "projectStaticFramework",
                                   targets: [staticFrameworkA, staticFrameworkB, staticLibrary])

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: path): Set([.target(name: staticFrameworkA.name, path: path),
                                                      .target(name: staticFrameworkB.name, path: path),
                                                      .target(name: staticLibrary.name, path: path)]),
            .target(name: staticFrameworkA.name, path: path): Set([.target(name: staticFrameworkB.name, path: path)]),
            .target(name: staticFrameworkB.name, path: path): Set([.target(name: staticLibrary.name, path: path)]),
            .target(name: staticLibrary.name, path: path): Set([]),
        ]

        let graph = ValueGraph.test(path: path,
                                    projects: [path: project],
                                    targets: [path: [appTarget.name: appTarget,
                                                     staticFrameworkA.name: staticFrameworkA,
                                                     staticFrameworkB.name: staticFrameworkB,
                                                     staticLibrary.name: staticLibrary]],
                                    dependencies: dependencies)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_when_staticLibrary_depends_on_static_products() throws {
        // Given
        let path: AbsolutePath = "/project"
        let appTarget = Target.test(name: "AppTarget", product: .app)
        let staticLibraryA = Target.test(name: "staticLibraryA", product: .staticLibrary)
        let staticLibraryB = Target.test(name: "staticLibraryB", product: .staticLibrary)
        let staticFramework = Target.test(name: "staticFramework", product: .staticFramework)

        let app = Project.test(path: path, name: "App", targets: [appTarget])
        let project = Project.test(path: "/tmp/staticframework",
                                   name: "projectStaticFramework",
                                   targets: [staticLibraryA, staticLibraryB, staticFramework])

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: path): Set([.target(name: staticLibraryA.name, path: path),
                                                      .target(name: staticLibraryB.name, path: path),
                                                      .target(name: staticFramework.name, path: path)]),
            .target(name: staticLibraryA.name, path: path): Set([.target(name: staticLibraryB.name, path: path)]),
            .target(name: staticLibraryB.name, path: path): Set([.target(name: staticFramework.name, path: path)]),
            .target(name: staticFramework.name, path: path): Set([]),
        ]

        let graph = ValueGraph.test(path: path,
                                    projects: [path: project],
                                    targets: [path: [appTarget.name: appTarget,
                                                     staticLibraryA.name: staticLibraryA,
                                                     staticLibraryB.name: staticLibraryB,
                                                     staticFramework.name: staticFramework]],
                                    dependencies: dependencies)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_frameworkDependsOnBundle() throws {
        // Given
        let path: AbsolutePath = "/project"
        let bundle = Target.empty(name: "bundle", product: .bundle)
        let framework = Target.empty(name: "framework", product: .framework)
        let project = Project.empty(path: path)

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: bundle.name, path: path): Set([]),
            .target(name: framework.name, path: path): Set([.target(name: bundle.name, path: path)]),
        ]

        let graph = ValueGraph.test(path: path,
                                    projects: [path: project],
                                    targets: [path: [bundle.name: bundle,
                                                     framework.name: framework]],
                                    dependencies: dependencies)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_applicationDependsOnBundle() throws {
        // Given
        let path: AbsolutePath = "/project"
        let bundle = Target.empty(name: "bundle", product: .bundle)
        let application = Target.empty(name: "application", product: .app)
        let project = Project.empty(path: path)

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: bundle.name, path: path): Set([]),
            .target(name: application.name, path: path): Set([.target(name: bundle.name, path: path)]),
        ]

        let graph = ValueGraph.test(path: path,
                                    projects: [path: project],
                                    targets: [path: [bundle.name: bundle,
                                                     application.name: application]],
                                    dependencies: dependencies)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_testTargetsDependsOnBundle() throws {
        // Given
        let path: AbsolutePath = "/project"
        let bundle = Target.empty(name: "bundle", product: .bundle)
        let unitTests = Target.empty(name: "unitTests", product: .unitTests)
        let uiTests = Target.empty(name: "uiTests", product: .unitTests)
        let project = Project.empty(path: path)

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: bundle.name, path: path): Set([]),
            .target(name: unitTests.name, path: path): Set([.target(name: bundle.name, path: path)]),
            .target(name: uiTests.name, path: path): Set([.target(name: bundle.name, path: path)]),
        ]

        let graph = ValueGraph.test(path: path,
                                    projects: [path: project],
                                    targets: [path: [bundle.name: bundle,
                                                     unitTests.name: unitTests,
                                                     uiTests.name: uiTests]],
                                    dependencies: dependencies)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_staticProductsCanDependOnDynamicFrameworks() throws {
        // Given
        let path: AbsolutePath = "/project"
        let staticFramework = Target.empty(name: "StaticFramework", product: .staticFramework)
        let staticLibrary = Target.empty(name: "StaticLibrary", product: .staticLibrary)
        let dynamicFramework = Target.empty(name: "DynamicFramework", product: .framework)
        let project = Project.empty(path: path)

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: staticLibrary.name, path: path): Set([.target(name: dynamicFramework.name, path: path)]),
            .target(name: staticFramework.name, path: path): Set([.target(name: dynamicFramework.name, path: path)]),
            .target(name: dynamicFramework.name, path: path): Set([]),
        ]

        let graph = ValueGraph.test(path: path,
                                    projects: [path: project],
                                    targets: [path: [staticFramework.name: staticFramework,
                                                     staticLibrary.name: staticLibrary,
                                                     dynamicFramework.name: dynamicFramework]],
                                    dependencies: dependencies)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_macStaticProductsCantDependOniOSStaticProducts() throws {
        // Given
        let path: AbsolutePath = "/project"
        let macStaticFramework = Target.empty(name: "MacStaticFramework", platform: .macOS, product: .staticFramework)
        let iosStaticFramework = Target.empty(name: "iOSStaticFramework", platform: .iOS, product: .staticFramework)
        let iosStaticLibrary = Target.empty(name: "iOSStaticLibrary", platform: .iOS, product: .staticLibrary)
        let project = Project.empty(path: path)

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: macStaticFramework.name, path: path): Set([.target(name: iosStaticFramework.name, path: path), .target(name: iosStaticLibrary.name, path: path)]),
            .target(name: iosStaticFramework.name, path: path): Set([]),
            .target(name: iosStaticLibrary.name, path: path): Set([]),
        ]

        let graph = ValueGraph.test(path: path,
                                    projects: [path: project],
                                    targets: [path: [macStaticFramework.name: macStaticFramework,
                                                     iosStaticFramework.name: iosStaticFramework,
                                                     iosStaticLibrary.name: iosStaticLibrary]],
                                    dependencies: dependencies)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertFalse(result.isEmpty)
    }

    func test_lint_watch_canDependOnWatchExtension() throws {
        // Given
        let path: AbsolutePath = "/project"
        let watchExtension = Target.empty(name: "WatckExtension", platform: .watchOS, product: .watch2Extension)
        let watchApp = Target.empty(name: "WatchApp", platform: .watchOS, product: .watch2App)
        let project = Project.empty(path: path)

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: watchApp.name, path: path): Set([.target(name: watchExtension.name, path: path)]),
            .target(name: watchExtension.name, path: path): Set([]),
        ]

        let graph = ValueGraph.test(path: path,
                                    projects: [path: project],
                                    targets: [path: [watchExtension.name: watchExtension,
                                                     watchApp.name: watchApp]],
                                    dependencies: dependencies)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_watch_canOnlyDependOnWatchExtension() throws {
        // Given
        let path: AbsolutePath = "/project"
        let invalidDependency = Target.empty(name: "Framework", platform: .watchOS, product: .framework)
        let watchApp = Target.empty(name: "WatchApp", platform: .watchOS, product: .watch2App)
        let project = Project.empty(path: path)

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: watchApp.name, path: path): Set([.target(name: invalidDependency.name, path: path)]),
            .target(name: invalidDependency.name, path: path): Set([]),
        ]

        let graph = ValueGraph.test(path: path,
                                    projects: [path: project],
                                    targets: [path: [invalidDependency.name: invalidDependency,
                                                     watchApp.name: watchApp]],
                                    dependencies: dependencies)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertFalse(result.isEmpty)
    }

    func test_lint_missingProjectConfigurationsFromDependencyProjects() throws {
        // Given
        let path: AbsolutePath = "/project"
        let customConfigurations: [BuildConfiguration: Configuration?] = [
            .debug("Debug"): nil,
            .debug("Testing"): nil,
            .release("Beta"): nil,
            .release("Release"): nil,
        ]
        let targetA = Target.empty(name: "TargetA", product: .framework)
        let projectAPath: AbsolutePath = "/path/to/a"
        let projectA = Project.empty(path: projectAPath, name: "ProjectA", settings: Settings(configurations: customConfigurations))

        let targetB = Target.empty(name: "TargetB", product: .framework)
        let projectBPath: AbsolutePath = "/path/to/b"
        let projectB = Project.empty(path: projectBPath, name: "ProjectB", settings: Settings(configurations: customConfigurations))

        let targetC = Target.empty(name: "TargetC", product: .framework)
        let projectCPath: AbsolutePath = "/path/to/c"
        let projectC = Project.empty(path: "/path/to/c", name: "ProjectC", settings: .default)

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: targetA.name, path: projectAPath): Set([.target(name: targetB.name, path: projectBPath)]),
            .target(name: targetB.name, path: projectBPath): Set([.target(name: targetC.name, path: projectCPath)]),
            .target(name: targetC.name, path: projectCPath): Set([]),
        ]
        let graph = ValueGraph.test(path: path,
                                    workspace: Workspace.test(projects: [projectAPath, projectBPath, projectCPath]),
                                    projects: [projectAPath: projectA,
                                               projectBPath: projectB,
                                               projectCPath: projectC],
                                    targets: [projectAPath: [targetA.name: targetA],
                                              projectBPath: [targetB.name: targetB],
                                              projectCPath: [targetC.name: targetC]],
                                    dependencies: dependencies)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(result, [
            LintingIssue(reason: "The project 'ProjectC' has missing or mismatching configurations. It has [Debug (debug), Release (release)], other projects have [Beta (release), Debug (debug), Release (release), Testing (debug)]",
                         severity: .warning),
        ])
    }

    func test_lint_mismatchingProjectConfigurationsFromDependencyProjects() throws {
        // Given
        let path: AbsolutePath = "/project"
        let customConfigurations: [BuildConfiguration: Configuration?] = [
            .debug("Debug"): nil,
            .debug("Testing"): nil,
            .release("Beta"): nil,
            .release("Release"): nil,
        ]
        let targetA = Target.empty(name: "TargetA", product: .framework)
        let projectAPath: AbsolutePath = "/path/to/a"
        let projectA = Project.empty(path: projectAPath, name: "ProjectA", settings: Settings(configurations: customConfigurations))

        let targetB = Target.empty(name: "TargetB", product: .framework)
        let projectBPath: AbsolutePath = "/path/to/b"
        let projectB = Project.empty(path: projectBPath, name: "ProjectB", settings: Settings(configurations: customConfigurations))

        let mismatchingConfigurations: [BuildConfiguration: Configuration?] = [
            .release("Debug"): nil,
            .release("Testing"): nil,
            .release("Beta"): nil,
            .release("Release"): nil,
        ]
        let targetC = Target.empty(name: "TargetC", product: .framework)
        let projectCPath: AbsolutePath = "/path/to/c"
        let projectC = Project.empty(path: projectCPath, name: "ProjectC", settings: Settings(configurations: mismatchingConfigurations))

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: targetA.name, path: projectAPath): Set([.target(name: targetB.name, path: projectBPath)]),
            .target(name: targetB.name, path: projectBPath): Set([.target(name: targetC.name, path: projectCPath)]),
            .target(name: targetC.name, path: projectCPath): Set([]),
        ]

        let graph = ValueGraph.test(path: path,
                                    workspace: Workspace.test(projects: [projectAPath]),
                                    projects: [projectAPath: projectA,
                                               projectBPath: projectB,
                                               projectCPath: projectC],
                                    targets: [projectAPath: [targetA.name: targetA],
                                              projectBPath: [targetB.name: targetB],
                                              projectCPath: [targetC.name: targetC]],
                                    dependencies: dependencies)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(result, [
            LintingIssue(reason: "The project 'ProjectC' has missing or mismatching configurations. It has [Beta (release), Debug (release), Release (release), Testing (release)], other projects have [Beta (release), Debug (debug), Release (release), Testing (debug)]",
                         severity: .warning),
        ])
    }

    func test_lint_doesNotFlagDependenciesWithExtraConfigurations() throws {
        // Lower level dependencies could be shared by projects in different workspaces as such
        // it is ok for them to contain more configurations than the entry node projects

        // Given
        let path: AbsolutePath = "/project"
        let customConfigurations: [BuildConfiguration: Configuration?] = [
            .debug("Debug"): nil,
            .release("Beta"): nil,
            .release("Release"): nil,
        ]
        let targetA = Target.empty(name: "TargetA", product: .framework)
        let projectAPath: AbsolutePath = "/path/to/a"
        let projectA = Project.empty(path: projectAPath, name: "ProjectA", settings: Settings(configurations: customConfigurations))

        let targetB = Target.empty(name: "TargetB", product: .framework)
        let projectBPath: AbsolutePath = "/path/to/b"
        let projectB = Project.empty(path: projectBPath, name: "ProjectB", settings: Settings(configurations: customConfigurations))

        let additionalConfigurations: [BuildConfiguration: Configuration?] = [
            .debug("Debug"): nil,
            .debug("Testing"): nil,
            .release("Beta"): nil,
            .release("Release"): nil,
        ]
        let targetC = Target.empty(name: "TargetC", product: .framework)
        let projectCPath: AbsolutePath = "/path/to/c"
        let projectC = Project.empty(path: projectCPath, name: "ProjectC", settings: Settings(configurations: additionalConfigurations))

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: targetA.name, path: projectAPath): Set([.target(name: targetB.name, path: projectBPath)]),
            .target(name: targetB.name, path: projectBPath): Set([.target(name: targetC.name, path: projectCPath)]),
            .target(name: targetC.name, path: projectCPath): Set([]),
        ]

        let graph = ValueGraph.test(path: path,
                                    workspace: Workspace.test(projects: [projectAPath, projectBPath]),
                                    projects: [projectAPath: projectA,
                                               projectBPath: projectB,
                                               projectCPath: projectC],
                                    targets: [projectAPath: [targetA.name: targetA],
                                              projectBPath: [targetB.name: targetB],
                                              projectCPath: [targetC.name: targetC]],
                                    dependencies: dependencies)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(result, [])
    }

    func test_lint_valid_watchTargetBundleIdentifiers() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App",
                              product: .app,
                              bundleId: "app")
        let watchApp = Target.test(name: "WatchApp",
                                   platform: .watchOS,
                                   product: .watch2App,
                                   bundleId: "app.watchapp")
        let watchExtension = Target.test(name: "WatchExtension",
                                         platform: .watchOS,
                                         product: .watch2Extension,
                                         bundleId: "app.watchapp.watchextension")
        let project = Project.test(path: path, targets: [app, watchApp, watchExtension])

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: path): Set([.target(name: watchApp.name, path: path)]),
            .target(name: watchApp.name, path: path): Set([.target(name: watchExtension.name, path: path)]),
            .target(name: watchExtension.name, path: path): Set([]),
        ]

        let graph = ValueGraph.test(path: path,
                                    workspace: Workspace.test(projects: [path]),
                                    projects: [path: project],
                                    targets: [path: [app.name: app, watchApp.name: watchApp, watchExtension.name: watchExtension]],
                                    dependencies: dependencies)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertTrue(got.isEmpty)
    }

    func test_lint_invalid_watchTargetBundleIdentifiers() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App",
                              product: .app,
                              bundleId: "app")
        let watchApp = Target.test(name: "WatchApp",
                                   platform: .watchOS,
                                   product: .watch2App,
                                   bundleId: "watchapp")
        let watchExtension = Target.test(name: "WatchExtension",
                                         platform: .watchOS,
                                         product: .watch2Extension,
                                         bundleId: "watchextension")
        let project = Project.test(targets: [app, watchApp, watchExtension])

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: path): Set([.target(name: watchApp.name, path: path)]),
            .target(name: watchApp.name, path: path): Set([.target(name: watchExtension.name, path: path)]),
            .target(name: watchExtension.name, path: path): Set([]),
        ]

        let graph = ValueGraph.test(path: path,
                                    workspace: Workspace.test(projects: [path]),
                                    projects: [path: project],
                                    targets: [path: [app.name: app, watchApp.name: watchApp, watchExtension.name: watchExtension]],
                                    dependencies: dependencies)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(got, [
            LintingIssue(reason: "Watch app 'WatchApp' bundleId: watchapp isn't prefixed with its parent's app 'app' bundleId 'app'",
                         severity: .error),
            LintingIssue(reason: "Watch extension 'WatchExtension' bundleId: watchextension isn't prefixed with its parent's watch app 'watchapp' bundleId 'watchapp'",
                         severity: .error),
        ])
    }

    func test_lint_valid_appClipTargetBundleIdentifiers() throws {
        // Given
        let temporaryPath = try self.temporaryPath()

        try createFiles([
            "entitlements/AppClip.entitlements",
        ])

        let entitlementsPath = temporaryPath.appending(RelativePath("entitlements/AppClip.entitlements"))

        let app = Target.test(name: "App",
                              product: .app,
                              bundleId: "com.example.app")
        let appClip = Target.test(name: "AppClip",
                                  platform: .iOS,
                                  product: .appClip,
                                  bundleId: "com.example.app.clip",
                                  entitlements: entitlementsPath)
        let project = Project.test(path: temporaryPath, targets: [app, appClip])
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: temporaryPath): Set([.target(name: appClip.name, path: temporaryPath)]),
            .target(name: appClip.name, path: temporaryPath): Set([]),
        ]

        let graph = ValueGraph.test(path: temporaryPath,
                                    workspace: Workspace.test(projects: [temporaryPath]),
                                    projects: [temporaryPath: project],
                                    targets: [temporaryPath: [app.name: app, appClip.name: appClip]],
                                    dependencies: dependencies)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertTrue(got.isEmpty)
    }

    func test_lint_invalid_appClipTargetBundleIdentifiers() throws {
        // Given
        let temporaryPath = try self.temporaryPath()

        try createFiles([
            "entitlements/AppClip.entitlements",
        ])

        let entitlementsPath = temporaryPath.appending(RelativePath("entitlements/AppClip.entitlements"))

        let app = Target.test(name: "TestApp",
                              product: .app,
                              bundleId: "com.example.app")
        let appClip = Target.test(name: "TestAppClip",
                                  platform: .iOS,
                                  product: .appClip,
                                  bundleId: "com.example1.app.clip",
                                  entitlements: entitlementsPath)
        let project = Project.test(targets: [app, appClip])

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: temporaryPath): Set([.target(name: appClip.name, path: temporaryPath)]),
            .target(name: appClip.name, path: temporaryPath): Set([]),
        ]

        let graph = ValueGraph.test(path: temporaryPath,
                                    workspace: Workspace.test(projects: [temporaryPath]),
                                    projects: [temporaryPath: project],
                                    targets: [temporaryPath: [app.name: app, appClip.name: appClip]],
                                    dependencies: dependencies)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(got, [
            LintingIssue(reason: "AppClip 'TestAppClip' bundleId: com.example1.app.clip isn't prefixed with its parent's app 'TestApp' bundleId 'com.example.app'",
                         severity: .error),
        ])
    }

    func test_lint_when_appclip_is_missing_required_entitlements() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App",
                              product: .app,
                              bundleId: "com.example.app")
        let appClip = Target.test(name: "AppClip",
                                  platform: .iOS,
                                  product: .appClip,
                                  bundleId: "com.example.app.clip")
        let project = Project.test(path: path, targets: [app, appClip])

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: path): Set([.target(name: appClip.name, path: path)]),
            .target(name: appClip.name, path: path): Set([]),
        ]

        let graph = ValueGraph.test(path: path,
                                    workspace: Workspace.test(projects: [path]),
                                    projects: [path: project],
                                    targets: [path: [app.name: app, appClip.name: appClip]],
                                    dependencies: dependencies)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(got, [
            LintingIssue(reason: "An AppClip 'AppClip' requires its Parent Application Identifiers Entitlement to be set",
                         severity: .error),
        ])
    }

    func test_lint_when_appclip_entitlements_does_not_exist() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App",
                              product: .app,
                              bundleId: "com.example.app")
        let appClip = Target.test(name: "AppClip",
                                  platform: .iOS,
                                  product: .appClip,
                                  bundleId: "com.example.app.clip",
                                  entitlements: "/entitlements/AppClip.entitlements")
        let project = Project.test(path: path, targets: [app, appClip])

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: path): Set([.target(name: appClip.name, path: path)]),
            .target(name: appClip.name, path: path): Set([]),
        ]

        let graph = ValueGraph.test(path: path,
                                    workspace: Workspace.test(projects: [path]),
                                    projects: [path: project],
                                    targets: [path: [app.name: app, appClip.name: appClip]],
                                    dependencies: dependencies)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(got, [
            LintingIssue(reason: "The entitlements at path '/entitlements/AppClip.entitlements' referenced by target does not exist",
                         severity: .error),
        ])
    }

    func test_lint_when_app_contains_more_than_one_appClip() throws {
        // Given
        let temporaryPath = try self.temporaryPath()

        try createFiles([
            "entitlements/AppClip.entitlements",
        ])

        let entitlementsPath = temporaryPath.appending(RelativePath("entitlements/AppClip.entitlements"))

        let app = Target.test(name: "App",
                              product: .app,
                              bundleId: "com.example.app")
        let appClip1 = Target.test(name: "AppClip1",
                                   platform: .iOS,
                                   product: .appClip,
                                   bundleId: "com.example.app.clip1",
                                   entitlements: entitlementsPath)

        let appClip2 = Target.test(name: "AppClip2",
                                   platform: .iOS,
                                   product: .appClip,
                                   bundleId: "com.example.app.clip2",
                                   entitlements: entitlementsPath)

        let project = Project.test(path: temporaryPath, targets: [app, appClip1, appClip2])

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: temporaryPath): Set([.target(name: appClip1.name, path: temporaryPath), .target(name: appClip2.name, path: temporaryPath)]),
            .target(name: appClip1.name, path: temporaryPath): Set([]),
            .target(name: appClip2.name, path: temporaryPath): Set([]),
        ]

        let graph = ValueGraph.test(path: temporaryPath,
                                    workspace: Workspace.test(projects: [temporaryPath]),
                                    projects: [temporaryPath: project],
                                    targets: [temporaryPath: [app.name: app, appClip1.name: appClip1, appClip2.name: appClip2]],
                                    dependencies: dependencies)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(got, [
            LintingIssue(reason: "Target 'App' at path '\(temporaryPath.pathString)' cannot depend on more than one app clip: AppClip1 and AppClip2",
                         severity: .error),
        ])
    }

    func test_lint_when_appClip_has_a_framework_dependency() throws {
        // Given
        let temporaryPath = try self.temporaryPath()

        try createFiles([
            "entitlements/AppClip.entitlements",
        ])

        let entitlementsPath = temporaryPath.appending(RelativePath("entitlements/AppClip.entitlements"))

        let framework = Target.empty(name: "Framework", product: .framework)

        let app = Target.test(name: "App",
                              product: .app,
                              bundleId: "com.example.app")
        let appClip = Target.test(name: "AppClip",
                                  platform: .iOS,
                                  product: .appClip,
                                  bundleId: "com.example.app.clip1",
                                  entitlements: entitlementsPath)

        let project = Project.test(path: temporaryPath, targets: [app, appClip, framework])

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: temporaryPath): Set([.target(name: appClip.name, path: temporaryPath)]),
            .target(name: appClip.name, path: temporaryPath): Set([.target(name: framework.name, path: temporaryPath)]),
        ]

        let graph = ValueGraph.test(path: temporaryPath,
                                    workspace: Workspace.test(projects: [temporaryPath]),
                                    projects: [temporaryPath: project],
                                    targets: [temporaryPath: [app.name: app, appClip.name: appClip, framework.name: framework]],
                                    dependencies: dependencies)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEmpty(got)
    }

    func test_lint_when_cli_tool_links_dynamic_framework() throws {
        // Given
        let path: AbsolutePath = "/project"
        let tool = Target.test(name: "App",
                               platform: .macOS,
                               product: .commandLineTool,
                               bundleId: "com.example.app")
        let dynamic = Target.test(name: "Dynamic",
                                  platform: .macOS,
                                  product: .framework,
                                  bundleId: "com.example.dynamic")

        let project = Project.test(path: path, targets: [tool, dynamic])

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: tool.name, path: path): Set([.target(name: dynamic.name, path: path)]),
            .target(name: dynamic.name, path: path): Set([]),
        ]

        let graph = ValueGraph.test(path: path,
                                    workspace: Workspace.test(projects: [path]),
                                    projects: [path: project],
                                    targets: [path: [tool.name: tool, dynamic.name: dynamic]],
                                    dependencies: dependencies)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(got, [
            LintingIssue(reason: "Target App has a dependency with target Dynamic of type framework for platform 'macOS' which is invalid or not supported yet.",
                         severity: .error),
        ])
    }

    func test_lint_when_cli_tool_links_dynamic_library() throws {
        // Given
        let path: AbsolutePath = "/project"
        let tool = Target.test(name: "App",
                               platform: .macOS,
                               product: .commandLineTool,
                               bundleId: "com.example.app")
        let dynamic = Target.test(name: "Dynamic",
                                  platform: .macOS,
                                  product: .dynamicLibrary,
                                  bundleId: "com.example.dynamic")

        let project = Project.test(path: path, targets: [tool, dynamic])

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: tool.name, path: path): Set([.target(name: dynamic.name, path: path)]),
            .target(name: dynamic.name, path: path): Set([]),
        ]

        let graph = ValueGraph.test(path: path,
                                    workspace: Workspace.test(projects: [path]),
                                    projects: [path: project],
                                    targets: [path: [tool.name: tool, dynamic.name: dynamic]],
                                    dependencies: dependencies)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEmpty(got)
    }

    func test_lint_when_cli_tool_links_supported_dependencies() throws {
        // Given
        let path: AbsolutePath = "/project"

        let tool = Target.test(name: "App",
                               platform: .macOS,
                               product: .commandLineTool,
                               bundleId: "com.example.app")
        let staticLib = Target.test(name: "StaticLib",
                                    platform: .macOS,
                                    product: .staticLibrary,
                                    bundleId: "com.example.staticlib")
        let staticFmwk = Target.test(name: "StaticFramework",
                                     platform: .macOS,
                                     product: .staticLibrary,
                                     bundleId: "com.example.staticfmwk")

        let project = Project.test(path: path, targets: [tool, staticLib, staticFmwk])

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: tool.name, path: path): Set([.target(name: staticLib.name, path: path), .target(name: staticFmwk.name, path: path)]),
            .target(name: staticLib.name, path: path): Set([]),
            .target(name: staticFmwk.name, path: path): Set([]),
        ]

        let graph = ValueGraph.test(path: path,
                                    workspace: Workspace.test(projects: [path]),
                                    projects: [path: project],
                                    targets: [path: [tool.name: tool, staticFmwk.name: staticFmwk, staticLib.name: staticLib]],
                                    dependencies: dependencies)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEmpty(got)
    }

    func test_lintDifferentBundleIdentifiers() {
        // Given
        let path: AbsolutePath = "/project"
        let appTarget = Target.test(name: "AppTarget", product: .app)
        let frameworkA = Target.test(name: "frameworkA", product: .framework, bundleId: "com.tuist.frameworks.test")
        let frameworkB = Target.test(name: "frameworkB", product: .framework, bundleId: "com.tuist.frameworks.test2")

        let app = Project.test(path: path, name: "App", targets: [appTarget])
        let frameworks1 = Project.test(path: "/tmp/frameworks1",
                                       name: "Frameworks1",
                                       targets: [frameworkA, frameworkB])

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: path): Set([.target(name: frameworkA.name, path: frameworks1.path),
                                                      .target(name: frameworkB.name, path: frameworks1.path)]),
        ]

        let project = Project.test(path: path, targets: [appTarget, frameworkA, frameworkB])

        let graph = ValueGraph.test(path: path,
                                    workspace: Workspace.test(projects: [path]),
                                    projects: [path: project],
                                    targets: [path: [appTarget.name: appTarget],
                                              frameworks1.path: [frameworkA.name: frameworkA, frameworkB.name: frameworkB]],
                                    dependencies: dependencies)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEmpty(got)
    }

    func test_lintDuplicateBundleIdentifiers() {
        // Given
        let path: AbsolutePath = "/project"
        let appTarget = Target.test(name: "AppTarget", product: .app)
        let frameworkA = Target.test(name: "frameworkA", product: .framework, bundleId: "com.tuist.frameworks.test")
        let frameworkB = Target.test(name: "frameworkB", product: .framework, bundleId: "com.tuist.frameworks.test")
        let frameworkC = Target.test(name: "frameworkC", product: .framework, bundleId: "com.tuist.frameworks.test2")
        let frameworkD = Target.test(name: "frameworkD", product: .framework, bundleId: "com.tuist.frameworks.test3")
        let frameworkE = Target.test(name: "frameworkE", product: .framework, bundleId: "com.tuist.frameworks.test2")
        let frameworkF = Target.test(name: "frameworkF", product: .framework, bundleId: "com.tuist.frameworks.test")

        let app = Project.test(path: path, name: "App", targets: [appTarget])
        let frameworks1 = Project.test(path: "/tmp/frameworks1",
                                       name: "Frameworks1",
                                       targets: [frameworkA, frameworkB])
        let frameworks2 = Project.test(path: "/tmp/frameworks2",
                                       name: "Frameworks2",
                                       targets: [frameworkC, frameworkD])
        let frameworks3 = Project.test(path: "/tmp/frameworks3",
                                       name: "Frameworks3",
                                       targets: [frameworkE, frameworkF])

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: path): Set([.target(name: frameworkA.name, path: frameworks1.path),
                                                      .target(name: frameworkB.name, path: frameworks1.path),
                                                      .target(name: frameworkC.name, path: frameworks2.path),
                                                      .target(name: frameworkD.name, path: frameworks2.path),
                                                      .target(name: frameworkE.name, path: frameworks3.path),
                                                      .target(name: frameworkF.name, path: frameworks3.path)]),
        ]

        let project = Project.test(path: path, targets: [appTarget, frameworkA, frameworkB, frameworkC, frameworkD, frameworkE, frameworkF])

        let graph = ValueGraph.test(path: path,
                                    workspace: Workspace.test(projects: [path]),
                                    projects: [path: project],
                                    targets: [path: [appTarget.name: appTarget],
                                              frameworks1.path: [frameworkA.name: frameworkA, frameworkB.name: frameworkB],
                                              frameworks2.path: [frameworkC.name: frameworkC, frameworkD.name: frameworkD],
                                              frameworks3.path: [frameworkE.name: frameworkE, frameworkF.name: frameworkF]],
                                    dependencies: dependencies)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(got, [
            LintingIssue(reason: "The bundle identifier 'com.tuist.frameworks.test' is being used by multiple targets: frameworkA, frameworkB, and frameworkF.", severity: .warning),
            LintingIssue(reason: "The bundle identifier 'com.tuist.frameworks.test2' is being used by multiple targets: frameworkC and frameworkE.", severity: .warning),
        ])
    }

    func test_lintBundleIdentifiersShouldIgnoreVariables() {
        // Given
        let path: AbsolutePath = "/project"
        let appTarget = Target.test(name: "AppTarget", product: .app)
        let frameworkA = Target.test(name: "frameworkA", product: .framework, bundleId: "${ANY_VARIABLE}")
        let frameworkB = Target.test(name: "frameworkB", product: .framework, bundleId: "${ANY_VARIABLE}")

        let app = Project.test(path: path, name: "App", targets: [appTarget])
        let frameworks1 = Project.test(path: "/tmp/frameworks1",
                                       name: "Frameworks1",
                                       targets: [frameworkA, frameworkB])

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: path): Set([.target(name: frameworkA.name, path: frameworks1.path),
                                                      .target(name: frameworkB.name, path: frameworks1.path)]),
        ]

        let project = Project.test(path: path, targets: [appTarget, frameworkA, frameworkB])

        let graph = ValueGraph.test(path: path,
                                    workspace: Workspace.test(projects: [path]),
                                    projects: [path: project],
                                    targets: [path: [appTarget.name: appTarget],
                                              frameworks1.path: [frameworkA.name: frameworkA, frameworkB.name: frameworkB]],
                                    dependencies: dependencies)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEmpty(got)
    }
}
