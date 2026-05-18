import XcodeProj

extension PBXNativeTarget {
    static func test(
        name: String = "App",
        buildConfigurationList: XCConfigurationList? = nil,
        buildRules: [PBXBuildRule] = [PBXBuildRule.test()],
        buildPhases: [PBXBuildPhase] = [
            PBXSourcesBuildPhase(files: []),
            PBXResourcesBuildPhase(files: []),
            PBXFrameworksBuildPhase(files: []),
        ],
        dependencies: [PBXTargetDependency] = [],
        productInstallPath: String? = nil,
        productName: String? = nil,
        productType: PBXProductType = .application,
        product: PBXFileReference? = PBXFileReference.test(
            sourceTree: .buildProductsDir,
            explicitFileType: "wrapper.application",
            path: "App.app",
            lastKnownFileType: nil,
            includeInIndex: false
        )
    ) -> PBXNativeTarget {
        PBXNativeTarget(
            name: name,
            buildConfigurationList: buildConfigurationList,
            buildPhases: buildPhases,
            buildRules: buildRules,
            dependencies: dependencies,
            productInstallPath: productInstallPath,
            productName: productName ?? name,
            product: product,
            productType: productType
        )
    }
}
