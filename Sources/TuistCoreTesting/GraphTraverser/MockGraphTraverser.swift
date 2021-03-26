import Foundation
import TSCBasic
import TuistGraph
@testable import TuistCore

// swiftlint:disable:next type_body_length
final class MockGraphTraverser: GraphTraversing {
    var invokedNameGetter = false
    var invokedNameGetterCount = 0
    var stubbedName: String! = ""

    var name: String {
        invokedNameGetter = true
        invokedNameGetterCount += 1
        return stubbedName
    }

    var invokedHasPackagesGetter = false
    var invokedHasPackagesGetterCount = 0
    var stubbedHasPackages: Bool! = false

    var hasPackages: Bool {
        invokedHasPackagesGetter = true
        invokedHasPackagesGetterCount += 1
        return stubbedHasPackages
    }

    var invokedHasRemotePackagesGetter = false
    var invokedHasRemotePackagesGetterCount = 0
    var stubbedHasRemotePackages: Bool! = false

    var hasRemotePackages: Bool {
        invokedHasRemotePackagesGetter = true
        invokedHasRemotePackagesGetterCount += 1
        return stubbedHasRemotePackages
    }

    var invokedPathGetter = false
    var invokedPathGetterCount = 0
    var stubbedPath: AbsolutePath!

    var path: AbsolutePath {
        invokedPathGetter = true
        invokedPathGetterCount += 1
        return stubbedPath
    }

    var invokedWorkspaceGetter = false
    var invokedWorkspaceGetterCount = 0
    var stubbedWorkspace: Workspace!

    var workspace: Workspace {
        invokedWorkspaceGetter = true
        invokedWorkspaceGetterCount += 1
        return stubbedWorkspace
    }

    var invokedProjectsGetter = false
    var invokedProjectsGetterCount = 0
    var stubbedProjects: [AbsolutePath: Project]! = [:]

    var projects: [AbsolutePath: Project] {
        invokedProjectsGetter = true
        invokedProjectsGetterCount += 1
        return stubbedProjects
    }

    var invokedTargetsGetter = false
    var invokedTargetsGetterCount = 0
    var stubbedTargets: [AbsolutePath: [String: Target]]! = [:]

    var targets: [AbsolutePath: [String: Target]] {
        invokedTargetsGetter = true
        invokedTargetsGetterCount += 1
        return stubbedTargets
    }

    var invokedDependenciesGetter = false
    var invokedDependenciesGetterCount = 0
    var stubbedDependencies: [ValueGraphDependency: Set<ValueGraphDependency>]! = [:]

    var dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] {
        invokedDependenciesGetter = true
        invokedDependenciesGetterCount += 1
        return stubbedDependencies
    }

    var invokedApps = false
    var invokedAppsCount = 0
    var stubbedAppsResult: Set<ValueGraphTarget>! = []

    func apps() -> Set<ValueGraphTarget> {
        invokedApps = true
        invokedAppsCount += 1
        return stubbedAppsResult
    }

    var invokedRootTargets = false
    var invokedRootTargetsCount = 0
    var stubbedRootTargetsResult: Set<ValueGraphTarget>! = []

    func rootTargets() -> Set<ValueGraphTarget> {
        invokedRootTargets = true
        invokedRootTargetsCount += 1
        return stubbedRootTargetsResult
    }

    var invokedCocoapodsPaths = false
    var invokedCocoapodsPathsCount = 0
    var stubbedCocoapodsPathsResult: Set<AbsolutePath>! = []

    func cocoapodsPaths() -> Set<AbsolutePath> {
        invokedCocoapodsPaths = true
        invokedCocoapodsPathsCount += 1
        return stubbedCocoapodsPathsResult
    }

    var invokedRootProjects = false
    var invokedRootProjectsCount = 0
    var stubbedRootProjectsResult: Set<Project>! = []

    func rootProjects() -> Set<Project> {
        invokedRootProjects = true
        invokedRootProjectsCount += 1
        return stubbedRootProjectsResult
    }

    var invokedAllTargets = false
    var invokedAllTargetsCount = 0
    var stubbedAllTargetsResult: Set<ValueGraphTarget>! = []

    func allTargets() -> Set<ValueGraphTarget> {
        invokedAllTargets = true
        invokedAllTargetsCount += 1
        return stubbedAllTargetsResult
    }

    var invokedPrecompiledFrameworksPaths = false
    var invokedPrecompiledFrameworksPathsCount = 0
    var stubbedPrecompiledFrameworksPathsResult: Set<AbsolutePath>! = []

    func precompiledFrameworksPaths() -> Set<AbsolutePath> {
        invokedPrecompiledFrameworksPaths = true
        invokedPrecompiledFrameworksPathsCount += 1
        return stubbedPrecompiledFrameworksPathsResult
    }

    var invokedTargetsProduct = false
    var invokedTargetsProductCount = 0
    var invokedTargetsProductParameters: (product: Product, Void)?
    var invokedTargetsProductParametersList = [(product: Product, Void)]()
    var stubbedTargetsProductResult: Set<ValueGraphTarget>! = []

    func targets(product: Product) -> Set<ValueGraphTarget> {
        invokedTargetsProduct = true
        invokedTargetsProductCount += 1
        invokedTargetsProductParameters = (product, ())
        invokedTargetsProductParametersList.append((product, ()))
        return stubbedTargetsProductResult
    }

    var invokedTarget = false
    var invokedTargetCount = 0
    var invokedTargetParameters: (path: AbsolutePath, name: String)?
    var invokedTargetParametersList = [(path: AbsolutePath, name: String)]()
    var stubbedTargetResult: ValueGraphTarget!

    func target(path: AbsolutePath, name: String) -> ValueGraphTarget? {
        invokedTarget = true
        invokedTargetCount += 1
        invokedTargetParameters = (path, name)
        invokedTargetParametersList.append((path, name))
        return stubbedTargetResult
    }

    var invokedTargetsAt = false
    var invokedTargetsAtCount = 0
    var invokedTargetsAtParameters: (path: AbsolutePath, Void)?
    var invokedTargetsAtParametersList = [(path: AbsolutePath, Void)]()
    var stubbedTargetsAtResult: Set<ValueGraphTarget>! = []

    func targets(at path: AbsolutePath) -> Set<ValueGraphTarget> {
        invokedTargetsAt = true
        invokedTargetsAtCount += 1
        invokedTargetsAtParameters = (path, ())
        invokedTargetsAtParametersList.append((path, ()))
        return stubbedTargetsAtResult
    }

    var invokedDirectLocalTargetDependencies = false

    var invokedDirectLocalTargetDependenciesCount = 0 // swiftlint:disable:this identifier_name
    var invokedDirectLocalTargetDependenciesParameters: (path: AbsolutePath, name: String)? // swiftlint:disable:this identifier_name
    var invokedDirectLocalTargetDependenciesParametersList = [(path: AbsolutePath, name: String)]() // swiftlint:disable:this identifier_name
    var stubbedDirectLocalTargetDependenciesResult: Set<ValueGraphTarget>! = [] // swiftlint:disable:this identifier_name

    func directLocalTargetDependencies(path: AbsolutePath, name: String) -> Set<ValueGraphTarget> {
        invokedDirectLocalTargetDependencies = true
        invokedDirectLocalTargetDependenciesCount += 1
        invokedDirectLocalTargetDependenciesParameters = (path, name)
        invokedDirectLocalTargetDependenciesParametersList.append((path, name))
        return stubbedDirectLocalTargetDependenciesResult
    }

    var invokedDirectTargetDependencies = false
    var invokedDirectTargetDependenciesCount = 0
    var invokedDirectTargetDependenciesParameters: (path: AbsolutePath, name: String)? // swiftlint:disable:this identifier_name
    var invokedDirectTargetDependenciesParametersList = [(path: AbsolutePath, name: String)]() // swiftlint:disable:this identifier_name
    var stubbedDirectTargetDependenciesResult: Set<ValueGraphTarget>! = []

    func directTargetDependencies(path: AbsolutePath, name: String) -> Set<ValueGraphTarget> {
        invokedDirectTargetDependencies = true
        invokedDirectTargetDependenciesCount += 1
        invokedDirectTargetDependenciesParameters = (path, name)
        invokedDirectTargetDependenciesParametersList.append((path, name))
        return stubbedDirectTargetDependenciesResult
    }

    var invokedAppExtensionDependencies = false
    var invokedAppExtensionDependenciesCount = 0
    var invokedAppExtensionDependenciesParameters: (path: AbsolutePath, name: String)? // swiftlint:disable:this identifier_name
    var invokedAppExtensionDependenciesParametersList = [(path: AbsolutePath, name: String)]() // swiftlint:disable:this identifier_name
    var stubbedAppExtensionDependenciesResult: Set<ValueGraphTarget>! = []

    func appExtensionDependencies(path: AbsolutePath, name: String) -> Set<ValueGraphTarget> {
        invokedAppExtensionDependencies = true
        invokedAppExtensionDependenciesCount += 1
        invokedAppExtensionDependenciesParameters = (path, name)
        invokedAppExtensionDependenciesParametersList.append((path, name))
        return stubbedAppExtensionDependenciesResult
    }

    var invokedResourceBundleDependencies = false
    var invokedResourceBundleDependenciesCount = 0
    var invokedResourceBundleDependenciesParameters: (path: AbsolutePath, name: String)? // swiftlint:disable:this identifier_name
    var invokedResourceBundleDependenciesParametersList = [(path: AbsolutePath, name: String)]() // swiftlint:disable:this identifier_name
    var stubbedResourceBundleDependenciesResult: Set<ValueGraphTarget>! = []

    func resourceBundleDependencies(path: AbsolutePath, name: String) -> Set<ValueGraphTarget> {
        invokedResourceBundleDependencies = true
        invokedResourceBundleDependenciesCount += 1
        invokedResourceBundleDependenciesParameters = (path, name)
        invokedResourceBundleDependenciesParametersList.append((path, name))
        return stubbedResourceBundleDependenciesResult
    }

    var invokedTestTargetsDependingOn = false
    var invokedTestTargetsDependingOnCount = 0
    var invokedTestTargetsDependingOnParameters: (path: AbsolutePath, name: String)?
    var invokedTestTargetsDependingOnParametersList = [(path: AbsolutePath, name: String)]() // swiftlint:disable:this identifier_name
    var stubbedTestTargetsDependingOnResult: Set<ValueGraphTarget>! = []

    func testTargetsDependingOn(path: AbsolutePath, name: String) -> Set<ValueGraphTarget> {
        invokedTestTargetsDependingOn = true
        invokedTestTargetsDependingOnCount += 1
        invokedTestTargetsDependingOnParameters = (path, name)
        invokedTestTargetsDependingOnParametersList.append((path, name))
        return stubbedTestTargetsDependingOnResult
    }

    var invokedDirectStaticDependencies = false
    var invokedDirectStaticDependenciesCount = 0
    var invokedDirectStaticDependenciesParameters: (path: AbsolutePath, name: String)? // swiftlint:disable:this identifier_name
    var invokedDirectStaticDependenciesParametersList = [(path: AbsolutePath, name: String)]() // swiftlint:disable:this identifier_name
    var stubbedDirectStaticDependenciesResult: Set<GraphDependencyReference>! = []

    func directStaticDependencies(path: AbsolutePath, name: String) -> Set<GraphDependencyReference> {
        invokedDirectStaticDependencies = true
        invokedDirectStaticDependenciesCount += 1
        invokedDirectStaticDependenciesParameters = (path, name)
        invokedDirectStaticDependenciesParametersList.append((path, name))
        return stubbedDirectStaticDependenciesResult
    }

    var invokedAppClipDependencies = false
    var invokedAppClipDependenciesCount = 0
    var invokedAppClipDependenciesParameters: (path: AbsolutePath, name: String)?
    var invokedAppClipDependenciesParametersList = [(path: AbsolutePath, name: String)]()
    var stubbedAppClipDependenciesResult: ValueGraphTarget!

    func appClipDependencies(path: AbsolutePath, name: String) -> ValueGraphTarget? {
        invokedAppClipDependencies = true
        invokedAppClipDependenciesCount += 1
        invokedAppClipDependenciesParameters = (path, name)
        invokedAppClipDependenciesParametersList.append((path, name))
        return stubbedAppClipDependenciesResult
    }

    var invokedEmbeddableFrameworks = false
    var invokedEmbeddableFrameworksCount = 0
    var invokedEmbeddableFrameworksParameters: (path: AbsolutePath, name: String)?
    var invokedEmbeddableFrameworksParametersList = [(path: AbsolutePath, name: String)]() // swiftlint:disable:this identifier_name
    var stubbedEmbeddableFrameworksResult: Set<GraphDependencyReference>! = []

    func embeddableFrameworks(path: AbsolutePath, name: String) -> Set<GraphDependencyReference> {
        invokedEmbeddableFrameworks = true
        invokedEmbeddableFrameworksCount += 1
        invokedEmbeddableFrameworksParameters = (path, name)
        invokedEmbeddableFrameworksParametersList.append((path, name))
        return stubbedEmbeddableFrameworksResult
    }

    var invokedLinkableDependencies = false
    var invokedLinkableDependenciesCount = 0
    var invokedLinkableDependenciesParameters: (path: AbsolutePath, name: String)?
    var invokedLinkableDependenciesParametersList = [(path: AbsolutePath, name: String)]() // swiftlint:disable:this identifier_name
    var stubbedLinkableDependenciesError: Error?
    var stubbedLinkableDependenciesResult: Set<GraphDependencyReference>! = []

    func linkableDependencies(path: AbsolutePath, name: String) throws -> Set<GraphDependencyReference> {
        invokedLinkableDependencies = true
        invokedLinkableDependenciesCount += 1
        invokedLinkableDependenciesParameters = (path, name)
        invokedLinkableDependenciesParametersList.append((path, name))
        if let error = stubbedLinkableDependenciesError {
            throw error
        }
        return stubbedLinkableDependenciesResult
    }

    var invokedCopyProductDependencies = false
    var invokedCopyProductDependenciesCount = 0
    var invokedCopyProductDependenciesParameters: (path: AbsolutePath, name: String)?
    var invokedCopyProductDependenciesParametersList = [(path: AbsolutePath, name: String)]() // swiftlint:disable:this identifier_name
    var stubbedCopyProductDependenciesResult: Set<GraphDependencyReference>! = []

    func copyProductDependencies(path: AbsolutePath, name: String) -> Set<GraphDependencyReference> {
        invokedCopyProductDependencies = true
        invokedCopyProductDependenciesCount += 1
        invokedCopyProductDependenciesParameters = (path, name)
        invokedCopyProductDependenciesParametersList.append((path, name))
        return stubbedCopyProductDependenciesResult
    }

    var invokedLibrariesPublicHeadersFolders = false
    var invokedLibrariesPublicHeadersFoldersCount = 0 // swiftlint:disable:this identifier_name
    var invokedLibrariesPublicHeadersFoldersParameters: (path: AbsolutePath, name: String)? // swiftlint:disable:this identifier_name
    var invokedLibrariesPublicHeadersFoldersParametersList = [(path: AbsolutePath, name: String)]() // swiftlint:disable:this identifier_name
    var stubbedLibrariesPublicHeadersFoldersResult: Set<AbsolutePath>! = [] // swiftlint:disable:this identifier_name

    func librariesPublicHeadersFolders(path: AbsolutePath, name: String) -> Set<AbsolutePath> {
        invokedLibrariesPublicHeadersFolders = true
        invokedLibrariesPublicHeadersFoldersCount += 1
        invokedLibrariesPublicHeadersFoldersParameters = (path, name)
        invokedLibrariesPublicHeadersFoldersParametersList.append((path, name))
        return stubbedLibrariesPublicHeadersFoldersResult
    }

    var invokedLibrariesSearchPaths = false
    var invokedLibrariesSearchPathsCount = 0
    var invokedLibrariesSearchPathsParameters: (path: AbsolutePath, name: String)?
    var invokedLibrariesSearchPathsParametersList = [(path: AbsolutePath, name: String)]() // swiftlint:disable:this identifier_name
    var stubbedLibrariesSearchPathsResult: Set<AbsolutePath>! = []

    func librariesSearchPaths(path: AbsolutePath, name: String) -> Set<AbsolutePath> {
        invokedLibrariesSearchPaths = true
        invokedLibrariesSearchPathsCount += 1
        invokedLibrariesSearchPathsParameters = (path, name)
        invokedLibrariesSearchPathsParametersList.append((path, name))
        return stubbedLibrariesSearchPathsResult
    }

    var invokedLibrariesSwiftIncludePaths = false
    var invokedLibrariesSwiftIncludePathsCount = 0
    var invokedLibrariesSwiftIncludePathsParameters: (path: AbsolutePath, name: String)? // swiftlint:disable:this identifier_name
    var invokedLibrariesSwiftIncludePathsParametersList = [(path: AbsolutePath, name: String)]() // swiftlint:disable:this identifier_name
    var stubbedLibrariesSwiftIncludePathsResult: Set<AbsolutePath>! = []

    func librariesSwiftIncludePaths(path: AbsolutePath, name: String) -> Set<AbsolutePath> {
        invokedLibrariesSwiftIncludePaths = true
        invokedLibrariesSwiftIncludePathsCount += 1
        invokedLibrariesSwiftIncludePathsParameters = (path, name)
        invokedLibrariesSwiftIncludePathsParametersList.append((path, name))
        return stubbedLibrariesSwiftIncludePathsResult
    }

    var invokedRunPathSearchPaths = false
    var invokedRunPathSearchPathsCount = 0
    var invokedRunPathSearchPathsParameters: (path: AbsolutePath, name: String)?
    var invokedRunPathSearchPathsParametersList = [(path: AbsolutePath, name: String)]()
    var stubbedRunPathSearchPathsResult: Set<AbsolutePath>! = []

    func runPathSearchPaths(path: AbsolutePath, name: String) -> Set<AbsolutePath> {
        invokedRunPathSearchPaths = true
        invokedRunPathSearchPathsCount += 1
        invokedRunPathSearchPathsParameters = (path, name)
        invokedRunPathSearchPathsParametersList.append((path, name))
        return stubbedRunPathSearchPathsResult
    }

    var invokedHostTargetFor = false
    var invokedHostTargetForCount = 0
    var invokedHostTargetForParameters: (path: AbsolutePath, name: String)?
    var invokedHostTargetForParametersList = [(path: AbsolutePath, name: String)]()
    var stubbedHostTargetForResult: ValueGraphTarget!

    func hostTargetFor(path: AbsolutePath, name: String) -> ValueGraphTarget? {
        invokedHostTargetFor = true
        invokedHostTargetForCount += 1
        invokedHostTargetForParameters = (path, name)
        invokedHostTargetForParametersList.append((path, name))
        return stubbedHostTargetForResult
    }

    var invokedAllProjectDependencies = false
    var invokedAllProjectDependenciesCount = 0
    var invokedAllProjectDependenciesParameters: (path: AbsolutePath, Void)?
    var invokedAllProjectDependenciesParametersList = [(path: AbsolutePath, Void)]() // swiftlint:disable:this identifier_name
    var stubbedAllProjectDependenciesError: Error?
    var stubbedAllProjectDependenciesResult: Set<GraphDependencyReference>! = []

    func allProjectDependencies(path: AbsolutePath) throws -> Set<GraphDependencyReference> {
        invokedAllProjectDependencies = true
        invokedAllProjectDependenciesCount += 1
        invokedAllProjectDependenciesParameters = (path, ())
        invokedAllProjectDependenciesParametersList.append((path, ()))
        if let error = stubbedAllProjectDependenciesError {
            throw error
        }
        return stubbedAllProjectDependenciesResult
    }

    var invokedDependsOnXCTest = false
    var invokedDependsOnXCTestCount = 0
    var invokedDependsOnXCTestParameters: (path: AbsolutePath, name: String)?
    var invokedDependsOnXCTestParametersList = [(path: AbsolutePath, name: String)]()
    var stubbedDependsOnXCTestResult: Bool! = false

    func dependsOnXCTest(path: AbsolutePath, name: String) -> Bool {
        invokedDependsOnXCTest = true
        invokedDependsOnXCTestCount += 1
        invokedDependsOnXCTestParameters = (path, name)
        invokedDependsOnXCTestParametersList.append((path, name))
        return stubbedDependsOnXCTestResult
    }

    var schemesStub: (() -> [Scheme])?
    func schemes() -> [Scheme] {
        schemesStub?() ?? []
    }
}
