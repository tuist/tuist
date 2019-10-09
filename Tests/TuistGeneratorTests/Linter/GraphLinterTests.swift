import Basic
import Foundation
import SPMUtility
import TuistCore
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator

final class GraphLinterTests: TuistUnitTestCase {
    var subject: GraphLinter!

    override func setUp() {
        super.setUp()
        subject = GraphLinter()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_lint_when_carthage_frameworks_are_missing() throws {
        let cache = GraphLoaderCache()
        let graph = Graph.test(cache: cache)

        let frameworkAPath = fileHandler.currentPath.appending(RelativePath("Carthage/Build/iOS/A.framework"))
        let frameworkBPath = fileHandler.currentPath.appending(RelativePath("Carthage/Build/iOS/B.framework"))

        try fileHandler.createFolder(frameworkAPath)

        let frameworkA = FrameworkNode(path: frameworkAPath)
        let frameworkB = FrameworkNode(path: frameworkBPath)

        cache.add(precompiledNode: frameworkA)
        cache.add(precompiledNode: frameworkB)

        let result = subject.lint(graph: graph)

        XCTAssertTrue(result.contains(LintingIssue(reason: "Framework not found at path \(frameworkBPath.pathString). The path might be wrong or Carthage dependencies not fetched", severity: .warning)))
    }

    func test_lint_when_podfiles_are_missing() throws {
        // Given
        let cache = GraphLoaderCache()
        let graph = Graph.test(cache: cache)
        let cocoapods = CocoaPodsNode(path: fileHandler.currentPath)
        cache.add(cocoapods: cocoapods)
        let podfilePath = fileHandler.currentPath.appending(component: "Podfile")

        // When
        let result = subject.lint(graph: graph)

        // Then
        XCTAssertTrue(result.contains(LintingIssue(reason: "The Podfile at path \(podfilePath) referenced by some projects does not exist", severity: .error)))
    }

    func test_lint_when_packages_and_xcode_10() throws {
        // Given
        let cache = GraphLoaderCache()
        let graph = Graph.test(cache: cache)
        let package = PackageNode(packageType: .local(path: RelativePath("A"), productName: "A"), path: fileHandler.currentPath)
        cache.add(package: package)
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
        let cache = GraphLoaderCache()
        let graph = Graph.test(cache: cache)
        let package = PackageNode(packageType: .local(path: RelativePath("A"), productName: "A"), path: fileHandler.currentPath)
        cache.add(package: package)
        let versionStub = Version(11, 0, 0)
        xcodeController.selectedVersionStub = .success(versionStub)

        // When
        let result = subject.lint(graph: graph)

        // Then
        XCTEmpty(result)
    }

    func test_lint_when_no_version_available() throws {
        // Given
        let cache = GraphLoaderCache()
        let graph = Graph.test(cache: cache)
        let package = PackageNode(packageType: .local(path: RelativePath("A"), productName: "A"), path: fileHandler.currentPath)
        cache.add(package: package)
        let error = NSError.test()
        xcodeController.selectedVersionStub = .failure(error)

        // When
        let result = subject.lint(graph: graph)

        // Then
        XCTAssertTrue(result.contains(LintingIssue(reason: "Could not determine Xcode version", severity: .error)))
    }

    func test_lint_when_frameworks_are_missing() throws {
        let cache = GraphLoaderCache()
        let graph = Graph.test(cache: cache)

        let frameworkAPath = fileHandler.currentPath.appending(component: "A.framework")
        let frameworkBPath = fileHandler.currentPath.appending(component: "B.framework")

        try fileHandler.createFolder(frameworkAPath)

        let frameworkA = FrameworkNode(path: frameworkAPath)
        let frameworkB = FrameworkNode(path: frameworkBPath)

        cache.add(precompiledNode: frameworkA)
        cache.add(precompiledNode: frameworkB)

        let result = subject.lint(graph: graph)

        XCTAssertTrue(result.contains(LintingIssue(reason: "Framework not found at path \(frameworkBPath.pathString)", severity: .error)))
    }

    func test_lint_when_package_dependency_linked_twice() throws {
        let cache = GraphLoaderCache()

        let appTarget = Target.test(name: "AppTarget", dependencies: [.package(.local(path: RelativePath("packageLibrary"), productName: "PackageLibrary")), .target(name: "frameworkA")])
        let frameworkTarget = Target.test(name: "frameworkA", dependencies: [.target(name: "staticFramework")])

        let app = Project.test(path: "/tmp/app", name: "App", targets: [appTarget])
        let projectFramework = Project.test(path: "/tmp/framework", name: "projectFramework", targets: [frameworkTarget])

        let package = PackageNode(packageType: .local(path: RelativePath("packageLibrary"), productName: "PackageLibrary"), path: "/tmp/packageLibrary")
        let framework = TargetNode(project: projectFramework, target: frameworkTarget, dependencies: [package])
        let appTargetNode = TargetNode(project: app, target: appTarget, dependencies: [package, framework])

        cache.add(project: app)
        cache.add(targetNode: appTargetNode)
        cache.add(targetNode: framework)
        cache.add(package: package)

        let graph = Graph.test(cache: cache, entryNodes: [appTargetNode, framework, package])

        let versionStub = Version(11, 0, 0)
        xcodeController.selectedVersionStub = .success(versionStub)

        let result = subject.lint(graph: graph)

        XCTAssertTrue(result.contains(LintingIssue(reason: "Package PackageLibrary has been linked against AppTarget and frameworkA, it is a static product so may introduce unwanted side effects.", severity: .warning)))
    }

    func test_lint_when_static_product_linked_twice() throws {
        let cache = GraphLoaderCache()

        let appTarget = Target.test(name: "AppTarget", dependencies: [.target(name: "staticFramework"), .target(name: "frameworkA")])
        let frameworkTarget = Target.test(name: "frameworkA", dependencies: [.target(name: "staticFramework")])
        let staticFrameworkTarget = Target.test(name: "staticFramework", product: .staticFramework)

        let app = Project.test(path: "/tmp/app", name: "App", targets: [appTarget])
        let projectFramework = Project.test(path: "/tmp/framework", name: "projectFramework", targets: [frameworkTarget])
        let projectStaticFramework = Project.test(path: "/tmp/staticframework", name: "projectStaticFramework", targets: [staticFrameworkTarget])

        let staticFramework = TargetNode(project: projectStaticFramework, target: staticFrameworkTarget, dependencies: [])
        let framework = TargetNode(project: projectFramework, target: frameworkTarget, dependencies: [staticFramework])
        let appTargetNode = TargetNode(project: app, target: appTarget, dependencies: [staticFramework, framework])

        cache.add(project: app)
        cache.add(targetNode: appTargetNode)
        cache.add(targetNode: framework)
        cache.add(targetNode: staticFramework)

        let graph = Graph.test(cache: cache, entryNodes: [appTargetNode, framework, staticFramework])

        let result = subject.lint(graph: graph)

        XCTAssertTrue(result.contains(LintingIssue(reason: "Target staticFramework has been linked against AppTarget and frameworkA, it is a static product so may introduce unwanted side effects.", severity: .warning)))
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

    func test_lint_staticTargetDependsOnBundle() throws {
        // Given
        let bundle = Target.empty(name: "bundle", product: .bundle)
        let staticFramework = Target.empty(name: "staticFramework", product: .staticFramework)
        let staticLibrary = Target.empty(name: "staticLibrary", product: .staticLibrary)
        let graph = Graph.create(project: .empty(),
                                 dependencies: [
                                     (target: bundle, dependencies: []),
                                     (target: staticFramework, dependencies: [bundle]),
                                     (target: staticLibrary, dependencies: [bundle]),
                                 ])

        // When
        let result = subject.lint(graph: graph)

        // Then
        let sortedResults = result.sorted { $0.reason < $1.reason }
        XCTAssertEqual(sortedResults, [
            LintingIssue(reason: "Target staticFramework has a dependency with target bundle of type bundle for platform 'iOS' which is invalid or not supported yet.", severity: .error),
            LintingIssue(reason: "Target staticLibrary has a dependency with target bundle of type bundle for platform 'iOS' which is invalid or not supported yet.", severity: .error),
        ])
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
}
