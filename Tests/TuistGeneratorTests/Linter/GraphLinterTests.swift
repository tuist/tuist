import Foundation
import TSCBasic
import struct TSCUtility.Version
import TuistCore
import TuistSupport
import XCTest

@testable import TuistGenerator
@testable import TuistSupportTesting

final class GraphLinterTests: TuistUnitTestCase {
    var subject: GraphLinter!

    override func setUp() {
        super.setUp()
        subject = GraphLinter(projectLinter: MockProjectLinter(),
                              staticProductsLinter: MockStaticProductsGraphLinter())
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_lint_when_carthage_frameworks_are_missing() throws {
        let temporaryPath = try self.temporaryPath()

        let frameworkAPath = temporaryPath.appending(RelativePath("Carthage/Build/iOS/A.framework"))
        let frameworkBPath = temporaryPath.appending(RelativePath("Carthage/Build/iOS/B.framework"))

        try FileHandler.shared.createFolder(frameworkAPath)

        let frameworkA = FrameworkNode.test(path: frameworkAPath)
        let frameworkB = FrameworkNode.test(path: frameworkBPath)

        let graph = Graph.test(precompiled: [frameworkA, frameworkB])

        let result = subject.lint(graph: graph)

        XCTAssertTrue(result.contains(LintingIssue(reason: "Framework not found at path \(frameworkBPath.pathString). The path might be wrong or Carthage dependencies not fetched", severity: .warning)))
    }

    func test_lint_when_podfiles_are_missing() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let cocoapods = CocoaPodsNode(path: temporaryPath)
        let graph = Graph.test(cocoapods: [cocoapods])
        let podfilePath = temporaryPath.appending(component: "Podfile")

        // When
        let result = subject.lint(graph: graph)

        // Then
        XCTAssertTrue(result.contains(LintingIssue(reason: "The Podfile at path \(podfilePath) referenced by some projects does not exist", severity: .error)))
    }

    func test_lint_when_packages_and_xcode_10() throws {
        // Given
        let package = Package.remote(url: "remote", requirement: .branch("master"))
        let project = Project.test(packages: [package])
        let graph = Graph.test(projects: [project], packages: [PackageNode(package: package, path: project.path)])
        let versionStub = Version(10, 0, 0)
        xcodeController.selectedVersionStub = .success(versionStub)

        // When
        let result = subject.lint(graph: graph)

        // Then
        let reason = "The project contains a SwiftPM package dependency but the selected version of Xcode is not compatible. Need at least 11 but got \(versionStub)"
        XCTAssertTrue(result.contains(LintingIssue(reason: reason, severity: .error)))
    }

    func test_lint_when_packages_and_xcode_11() throws {
        // Given
        let project = Project.test(packages: [
            .remote(url: "remote", requirement: .branch("master")),
        ])

        let graph = Graph.test(projects: [project])
        let versionStub = Version(11, 0, 0)
        xcodeController.selectedVersionStub = .success(versionStub)

        // When

        let result = subject.lint(graph: graph)

        // Then
        let reason = "The project contains a SwiftPM package dependency but the selected version of Xcode is not compatible. Need at least 11 but got \(versionStub)"
        XCTAssertFalse(result.contains(LintingIssue(reason: reason, severity: .error)))
    }

    func test_lint_when_no_version_available() throws {
        // Given
        let package = Package.remote(url: "remote", requirement: .branch("master"))
        let project = Project.test(packages: [package])
        let graph = Graph.test(projects: [project], packages: [PackageNode(package: package, path: project.path)])

        let error = NSError.test()
        xcodeController.selectedVersionStub = .failure(error)

        // When
        let result = subject.lint(graph: graph)

        // Then
        XCTAssertTrue(result.contains(LintingIssue(reason: "Could not determine Xcode version", severity: .error)))
    }

    func test_lint_when_frameworks_are_missing() throws {
        let temporaryPath = try self.temporaryPath()

        let frameworkAPath = temporaryPath.appending(component: "A.framework")
        let frameworkBPath = temporaryPath.appending(component: "B.framework")

        try FileHandler.shared.createFolder(frameworkAPath)

        let frameworkA = FrameworkNode.test(path: frameworkAPath)
        let frameworkB = FrameworkNode.test(path: frameworkBPath)

        let graph = Graph.test(precompiled: [frameworkA, frameworkB])

        let result = subject.lint(graph: graph)

        XCTAssertTrue(result.contains(LintingIssue(reason: "Framework not found at path \(frameworkBPath.pathString)", severity: .error)))
    }

    func test_lint_when_staticFramework_depends_on_static_products() throws {
        // Given
        let appTarget = Target.test(name: "AppTarget", product: .app)
        let staticFrameworkA = Target.test(name: "staticFrameworkA", product: .staticFramework)
        let staticFrameworkB = Target.test(name: "staticFrameworkB", product: .staticFramework)
        let staticLibrary = Target.test(name: "staticLibrary", product: .staticLibrary)

        let app = Project.test(path: "/tmp/app", name: "App", targets: [appTarget])
        let frameworks = Project.test(path: "/tmp/staticframework",
                                      name: "projectStaticFramework",
                                      targets: [staticFrameworkA, staticFrameworkB, staticLibrary])

        let graph = Graph.create(dependencies: [
            (project: app, target: appTarget, dependencies: [staticFrameworkA, staticFrameworkB, staticLibrary]),
            (project: frameworks, target: staticFrameworkA, dependencies: [staticFrameworkB]),
            (project: frameworks, target: staticFrameworkB, dependencies: [staticLibrary]),
            (project: frameworks, target: staticLibrary, dependencies: []),
        ])

        // When
        let result = subject.lint(graph: graph)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_when_staticLibrary_depends_on_static_products() throws {
        // Given
        let appTarget = Target.test(name: "AppTarget", product: .app)
        let staticLibraryA = Target.test(name: "staticLibraryA", product: .staticLibrary)
        let staticLibraryB = Target.test(name: "staticLibraryB", product: .staticLibrary)
        let staticFramework = Target.test(name: "staticFramework", product: .staticFramework)

        let app = Project.test(path: "/tmp/app", name: "App", targets: [appTarget])
        let frameworks = Project.test(path: "/tmp/staticframework",
                                      name: "projectStaticFramework",
                                      targets: [staticLibraryA, staticLibraryB, staticFramework])

        let graph = Graph.create(dependencies: [
            (project: app, target: appTarget, dependencies: [staticLibraryA, staticLibraryB, staticFramework]),
            (project: frameworks, target: staticLibraryA, dependencies: [staticLibraryB]),
            (project: frameworks, target: staticLibraryB, dependencies: [staticFramework]),
            (project: frameworks, target: staticFramework, dependencies: []),
        ])

        // When
        let result = subject.lint(graph: graph)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_frameworkDependsOnBundle() throws {
        // Given
        let bundle = Target.empty(name: "bundle", product: .bundle)
        let framework = Target.empty(name: "framework", product: .framework)
        let graph = Graph.create(project: .empty(),
                                 dependencies: [
                                     (target: bundle, dependencies: []),
                                     (target: framework, dependencies: [bundle]),
                                 ])

        // When
        let result = subject.lint(graph: graph)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_applicationDependsOnBundle() throws {
        // Given
        let bundle = Target.empty(name: "bundle", product: .bundle)
        let application = Target.empty(name: "application", product: .app)
        let graph = Graph.create(project: .empty(),
                                 dependencies: [
                                     (target: bundle, dependencies: []),
                                     (target: application, dependencies: [bundle]),
                                 ])

        // When
        let result = subject.lint(graph: graph)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_testTargetsDependsOnBundle() throws {
        // Given
        let bundle = Target.empty(name: "bundle", product: .bundle)
        let unitTests = Target.empty(name: "unitTests", product: .unitTests)
        let uiTests = Target.empty(name: "uiTests", product: .unitTests)
        let graph = Graph.create(project: .empty(),
                                 dependencies: [
                                     (target: bundle, dependencies: []),
                                     (target: unitTests, dependencies: [bundle]),
                                     (target: uiTests, dependencies: [bundle]),
                                 ])

        // When
        let result = subject.lint(graph: graph)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_staticProductsCanDependOnDynamicFrameworks() throws {
        // Given
        let staticFramework = Target.empty(name: "StaticFramework", product: .staticFramework)
        let staticLibrary = Target.empty(name: "StaticLibrary", product: .staticLibrary)
        let dynamicFramework = Target.empty(name: "DynamicFramework", product: .framework)
        let graph = Graph.create(project: .empty(),
                                 dependencies: [
                                     (target: staticLibrary, dependencies: [dynamicFramework]),
                                     (target: staticFramework, dependencies: [dynamicFramework]),
                                     (target: dynamicFramework, dependencies: []),
                                 ])

        // When
        let result = subject.lint(graph: graph)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_macStaticProductsCantDependOniOSStaticProducts() throws {
        // Given
        let macStaticFramework = Target.empty(name: "MacStaticFramework", platform: .macOS, product: .staticFramework)
        let iosStaticFramework = Target.empty(name: "iOSStaticFramework", platform: .iOS, product: .staticFramework)
        let iosStaticLibrary = Target.empty(name: "iOSStaticLibrary", platform: .iOS, product: .staticLibrary)
        let graph = Graph.create(project: .empty(),
                                 dependencies: [
                                     (target: macStaticFramework, dependencies: [iosStaticFramework, iosStaticLibrary]),
                                     (target: iosStaticFramework, dependencies: []),
                                     (target: iosStaticLibrary, dependencies: []),
                                 ])

        // When
        let result = subject.lint(graph: graph)

        // Then
        XCTAssertFalse(result.isEmpty)
    }

    func test_lint_watch_canDependOnWatchExtension() throws {
        // Given
        let watchExtension = Target.empty(name: "WatckExtension", platform: .watchOS, product: .watch2Extension)
        let watchApp = Target.empty(name: "WatchApp", platform: .watchOS, product: .watch2App)
        let graph = Graph.create(project: .empty(),
                                 dependencies: [
                                     (target: watchApp, dependencies: [watchExtension]),
                                     (target: watchExtension, dependencies: []),
                                 ])

        // When
        let result = subject.lint(graph: graph)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_watch_canOnlyDependOnWatchExtension() throws {
        // Given
        let invalidDependency = Target.empty(name: "Framework", platform: .watchOS, product: .framework)
        let watchApp = Target.empty(name: "WatchApp", platform: .watchOS, product: .watch2App)
        let graph = Graph.create(project: .empty(),
                                 dependencies: [
                                     (target: watchApp, dependencies: [invalidDependency]),
                                     (target: invalidDependency, dependencies: []),
                                 ])

        // When
        let result = subject.lint(graph: graph)

        // Then
        XCTAssertFalse(result.isEmpty)
    }

    func test_lint_missingProjectConfigurationsFromDependencyProjects() throws {
        // Given
        let customConfigurations: [BuildConfiguration: Configuration?] = [
            .debug("Debug"): nil,
            .debug("Testing"): nil,
            .release("Beta"): nil,
            .release("Release"): nil,
        ]
        let targetA = Target.empty(name: "TargetA", product: .framework)
        let projectA = Project.empty(path: "/path/to/a", name: "ProjectA", settings: Settings(configurations: customConfigurations))

        let targetB = Target.empty(name: "TargetB", product: .framework)
        let projectB = Project.empty(path: "/path/to/b", name: "ProjectB", settings: Settings(configurations: customConfigurations))

        let targetC = Target.empty(name: "TargetC", product: .framework)
        let projectC = Project.empty(path: "/path/to/c", name: "ProjectC", settings: .default)

        let graph = Graph.create(projects: [projectA, projectB, projectC],
                                 dependencies: [
                                     (project: projectA, target: targetA, dependencies: [targetB]),
                                     (project: projectB, target: targetB, dependencies: [targetC]),
                                     (project: projectC, target: targetC, dependencies: []),
                                 ])

        // When
        let result = subject.lint(graph: graph)

        // Then
        XCTAssertEqual(result, [
            LintingIssue(reason: "The project 'ProjectC' has missing or mismatching configurations. It has [Debug (debug), Release (release)], other projects have [Beta (release), Debug (debug), Release (release), Testing (debug)]",
                         severity: .warning),
        ])
    }

    func test_lint_mismatchingProjectConfigurationsFromDependencyProjects() throws {
        // Given
        let customConfigurations: [BuildConfiguration: Configuration?] = [
            .debug("Debug"): nil,
            .debug("Testing"): nil,
            .release("Beta"): nil,
            .release("Release"): nil,
        ]
        let targetA = Target.empty(name: "TargetA", product: .framework)
        let projectA = Project.empty(path: "/path/to/a", name: "ProjectA", settings: Settings(configurations: customConfigurations))

        let targetB = Target.empty(name: "TargetB", product: .framework)
        let projectB = Project.empty(path: "/path/to/b", name: "ProjectB", settings: Settings(configurations: customConfigurations))

        let mismatchingConfigurations: [BuildConfiguration: Configuration?] = [
            .release("Debug"): nil,
            .release("Testing"): nil,
            .release("Beta"): nil,
            .release("Release"): nil,
        ]
        let targetC = Target.empty(name: "TargetC", product: .framework)
        let projectC = Project.empty(path: "/path/to/c", name: "ProjectC", settings: Settings(configurations: mismatchingConfigurations))

        let graph = Graph.create(projects: [projectA, projectB, projectC],
                                 entryNodes: [targetA],
                                 dependencies: [
                                     (project: projectA, target: targetA, dependencies: [targetB]),
                                     (project: projectB, target: targetB, dependencies: [targetC]),
                                     (project: projectC, target: targetC, dependencies: []),
                                 ])

        // When
        let result = subject.lint(graph: graph)

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
        let customConfigurations: [BuildConfiguration: Configuration?] = [
            .debug("Debug"): nil,
            .release("Beta"): nil,
            .release("Release"): nil,
        ]
        let targetA = Target.empty(name: "TargetA", product: .framework)
        let projectA = Project.empty(path: "/path/to/a", name: "ProjectA", settings: Settings(configurations: customConfigurations))

        let targetB = Target.empty(name: "TargetB", product: .framework)
        let projectB = Project.empty(path: "/path/to/b", name: "ProjectB", settings: Settings(configurations: customConfigurations))

        let additionalConfigurations: [BuildConfiguration: Configuration?] = [
            .debug("Debug"): nil,
            .debug("Testing"): nil,
            .release("Beta"): nil,
            .release("Release"): nil,
        ]
        let targetC = Target.empty(name: "TargetC", product: .framework)
        let projectC = Project.empty(path: "/path/to/c", name: "ProjectC", settings: Settings(configurations: additionalConfigurations))

        let graph = Graph.create(projects: [projectA, projectB, projectC],
                                 entryNodes: [targetA],
                                 dependencies: [
                                     (project: projectA, target: targetA, dependencies: [targetB]),
                                     (project: projectB, target: targetB, dependencies: [targetC]),
                                     (project: projectC, target: targetC, dependencies: []),
                                 ])

        // When
        let result = subject.lint(graph: graph)

        // Then
        XCTAssertEqual(result, [])
    }

    func test_lint_valid_watchTargetBundleIdentifiers() throws {
        // Given
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
        let project = Project.test(targets: [app, watchApp, watchExtension])
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: app, dependencies: [watchApp]),
                                     (target: watchApp, dependencies: [watchExtension]),
                                     (target: watchExtension, dependencies: []),
                                 ])

        // When
        let got = subject.lint(graph: graph)

        // Then
        XCTAssertTrue(got.isEmpty)
    }

    func test_lint_invalid_watchTargetBundleIdentifiers() throws {
        // Given
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
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: app, dependencies: [watchApp]),
                                     (target: watchApp, dependencies: [watchExtension]),
                                     (target: watchExtension, dependencies: []),
                                 ])

        // When
        let got = subject.lint(graph: graph)

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
        let project = Project.test(targets: [app, appClip])
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: app, dependencies: [appClip]),
                                     (target: appClip, dependencies: []),
                                 ])

        // When
        let got = subject.lint(graph: graph)

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
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: app, dependencies: [appClip]),
                                     (target: appClip, dependencies: []),
                                 ])

        // When
        let got = subject.lint(graph: graph)

        // Then
        XCTAssertEqual(got, [
            LintingIssue(reason: "AppClip 'TestAppClip' bundleId: com.example1.app.clip isn't prefixed with its parent's app 'TestApp' bundleId 'com.example.app'",
                         severity: .error),
        ])
    }

    func test_lint_when_appclip_is_missing_required_entitlements() throws {
        // Given
        let app = Target.test(name: "App",
                              product: .app,
                              bundleId: "com.example.app")
        let appClip = Target.test(name: "AppClip",
                                  platform: .iOS,
                                  product: .appClip,
                                  bundleId: "com.example.app.clip")
        let project = Project.test(targets: [app, appClip])
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: app, dependencies: [appClip]),
                                     (target: appClip, dependencies: []),
                                 ])

        // When
        let got = subject.lint(graph: graph)

        // Then
        XCTAssertEqual(got, [
            LintingIssue(reason: "An AppClip 'AppClip' requires its Parent Application Identifiers Entitlement to be set",
                         severity: .error),
        ])
    }

    func test_lint_when_appclip_entitlements_does_not_exist() throws {
        // Given
        let app = Target.test(name: "App",
                              product: .app,
                              bundleId: "com.example.app")
        let appClip = Target.test(name: "AppClip",
                                  platform: .iOS,
                                  product: .appClip,
                                  bundleId: "com.example.app.clip",
                                  entitlements: "/entitlements/AppClip.entitlements")
        let project = Project.test(targets: [app, appClip])
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: app, dependencies: [appClip]),
                                     (target: appClip, dependencies: []),
                                 ])

        // When
        let got = subject.lint(graph: graph)

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

        let project = Project.test(targets: [app, appClip1, appClip2])
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: app, dependencies: [appClip1, appClip2]),
                                     (target: appClip1, dependencies: []),
                                     (target: appClip2, dependencies: []),
                                 ])

        // When
        let got = subject.lint(graph: graph)

        // Then
        XCTAssertEqual(got, [
            LintingIssue(reason: "App 'App' cannot depend on more than one app clip -> AppClip1, AppClip2",
                         severity: .error),
        ])
    }
    
    func test_lint_when_cli_tool_links_dynamic_framework() throws {
        // Given
        let tool = Target.test(name: "App",
                               platform: .macOS,
                               product: .commandLineTool,
                               bundleId: "com.example.app")
        let dynamic = Target.test(name: "Dynamic",
                                  platform: .macOS,
                                  product: .framework,
                                  bundleId: "com.example.dynamic")

        let project = Project.test(targets: [tool, dynamic])
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: tool, dependencies: [dynamic]),
                                     (target: dynamic, dependencies: []),
                                 ])

        // When
        let got = subject.lint(graph: graph)

        // Then
        XCTAssertEqual(got, [
            LintingIssue(reason: "Target App has a dependency with target Dynamic of type framework for platform 'macOS' which is invalid or not supported yet.",
                         severity: .error),
        ])
    }
    
    func test_lint_when_cli_tool_links_dynamic_library() throws {
        // Given
        let tool = Target.test(name: "App",
                               platform: .macOS,
                               product: .commandLineTool,
                               bundleId: "com.example.app")
        let dynamic = Target.test(name: "Dynamic",
                                  platform: .macOS,
                                  product: .dynamicLibrary,
                                  bundleId: "com.example.dynamic")

        let project = Project.test(targets: [tool, dynamic])
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: tool, dependencies: [dynamic]),
                                     (target: dynamic, dependencies: []),
                                 ])

        // When
        let got = subject.lint(graph: graph)

        // Then
        XCTAssertEqual(got, [
            LintingIssue(reason: "Target App has a dependency with target Dynamic of type dynamic library for platform 'macOS' which is invalid or not supported yet.",
                         severity: .error),
        ])
    }
    
    func test_lint_when_cli_tool_links_supported_dependencies() throws {
        // Given
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

        let project = Project.test(targets: [tool, staticLib, staticFmwk])
        let graph = Graph.create(project: project,
                                 dependencies: [
                                    (target: tool, dependencies: [staticLib, staticFmwk]),
                                    (target: staticLib, dependencies: []),
                                    (target: staticFmwk, dependencies: []),
                                 ])

        // When
        let got = subject.lint(graph: graph)

        // Then
        XCTAssertEmpty(got)
    }
}
