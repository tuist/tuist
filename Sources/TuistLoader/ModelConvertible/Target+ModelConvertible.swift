import Basic
import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.Target: ModelConvertible {
    // swiftlint:disable:next function_body_length
    init(manifest: ProjectDescription.Target, generatorPaths: GeneratorPaths) throws {
        let name = manifest.name
        let platform = try TuistCore.Platform(manifest: manifest.platform, generatorPaths: generatorPaths)
        let product = try TuistCore.Product(manifest: manifest.product, generatorPaths: generatorPaths)

        let bundleId = manifest.bundleId
        let productName = manifest.productName
        let deploymentTarget = try manifest.deploymentTarget.map { try TuistCore.DeploymentTarget(manifest: $0, generatorPaths: generatorPaths) }

        let dependencies = try manifest.dependencies.map { try TuistCore.Dependency(manifest: $0, generatorPaths: generatorPaths) }

        let infoPlist = try TuistCore.InfoPlist(manifest: manifest.infoPlist, generatorPaths: generatorPaths)
        let entitlements = try manifest.entitlements.map { try generatorPaths.resolve(path: $0) }

        let settings = try manifest.settings.map { try TuistCore.Settings(manifest: $0, generatorPaths: generatorPaths) }
        let sources = try TuistCore.Target.sources(projectPath: generatorPaths.manifestDirectory, sources: manifest.sources?.globs.map {
            let glob = try generatorPaths.resolve(path: $0.glob).pathString
            let excluding = try $0.excluding.map { try generatorPaths.resolve(path: $0).pathString }
            return (glob: glob, excluding: excluding, compilerFlags: $0.compilerFlags)
        } ?? [])

        let resources = try (manifest.resources ?? []).compactMap {
            try TuistCore.FileElements(manifest: $0, generatorPaths: generatorPaths)
                .filter({ TuistCore.Target.isResource(path: $0) })
        }

        let headers = try manifest.headers.map { try TuistCore.Headers(manifest: $0, generatorPaths: generatorPaths) }

        let coreDataModels = try manifest.coreDataModels.map {
            try TuistCore.CoreDataModel(manifest: $0, generatorPaths: generatorPaths)
        }

        let actions = try manifest.actions.map { try TuistCore.TargetAction(manifest: $0, generatorPaths: generatorPaths) }
        let environment = manifest.environment

        self.init(name: name,
                  platform: platform,
                  product: product,
                  productName: productName,
                  bundleId: bundleId,
                  deploymentTarget: deploymentTarget,
                  infoPlist: infoPlist,
                  entitlements: entitlements,
                  settings: settings,
                  sources: sources,
                  resources: resources,
                  headers: headers,
                  coreDataModels: coreDataModels,
                  actions: actions,
                  environment: environment,
                  filesGroup: .group(name: "Project"),
                  dependencies: dependencies)
    }
}
