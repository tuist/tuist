import Foundation
import TSCBasic
@testable import TuistCore

final class MockGraphTraverser: GraphTraversing {
    var invokedDirectTargetDependencies = false
    var invokedDirectTargetDependenciesCount = 0
    var invokedDirectTargetDependenciesParameters: (path: AbsolutePath, name: String)?
    var invokedDirectTargetDependenciesParametersList = [(path: AbsolutePath, name: String)]()
    var stubbedDirectTargetDependenciesResult: [Target]! = []

    func directTargetDependencies(path: AbsolutePath, name: String) -> [Target] {
        invokedDirectTargetDependencies = true
        invokedDirectTargetDependenciesCount += 1
        invokedDirectTargetDependenciesParameters = (path, name)
        invokedDirectTargetDependenciesParametersList.append((path, name))
        return stubbedDirectTargetDependenciesResult
    }

    var invokedAppExtensionDependencies = false
    var invokedAppExtensionDependenciesCount = 0
    var invokedAppExtensionDependenciesParameters: (path: AbsolutePath, name: String)?
    var invokedAppExtensionDependenciesParametersList = [(path: AbsolutePath, name: String)]()
    var stubbedAppExtensionDependenciesResult: [Target]! = []

    func appExtensionDependencies(path: AbsolutePath, name: String) -> [Target] {
        invokedAppExtensionDependencies = true
        invokedAppExtensionDependenciesCount += 1
        invokedAppExtensionDependenciesParameters = (path, name)
        invokedAppExtensionDependenciesParametersList.append((path, name))
        return stubbedAppExtensionDependenciesResult
    }

    var invokedResourceBundleDependencies = false
    var invokedResourceBundleDependenciesCount = 0
    var invokedResourceBundleDependenciesParameters: (path: AbsolutePath, name: String)?
    var invokedResourceBundleDependenciesParametersList = [(path: AbsolutePath, name: String)]()
    var stubbedResourceBundleDependenciesResult: [Target]! = []

    func resourceBundleDependencies(path: AbsolutePath, name: String) -> [Target] {
        invokedResourceBundleDependencies = true
        invokedResourceBundleDependenciesCount += 1
        invokedResourceBundleDependenciesParameters = (path, name)
        invokedResourceBundleDependenciesParametersList.append((path, name))
        return stubbedResourceBundleDependenciesResult
    }
}
