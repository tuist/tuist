import Path
import Testing
import XcodeGraph
import XcodeProj
@testable import XcodeGraphMapper

@Suite
struct DependencyMapperTests {
    let mapper: PBXTargetDependencyMapping

    init() {
        mapper = PBXTargetDependencyMapper()
    }

    @Test("Maps direct target dependencies correctly")
    func directTargetMapping() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()
        let pbxProj = xcodeProj.pbxproj
        let target = try PBXNativeTarget.test(
            name: "DirectTarget",
            productType: .application
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        let dep = PBXTargetDependency(
            name: "DirectTarget",
            target: target
        ).add(to: pbxProj)

        try PBXNativeTarget.test(
            name: "App",
            dependencies: [dep],
            productType: .application
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        // When
        let mapped = try mapper.map(dep, xcodeProj: xcodeProj)

        // Then
        #expect(mapped == .target(name: "DirectTarget", status: .required, condition: nil))
    }

    @Test("Maps package product dependencies to runtime package targets")
    func packageProductMapping() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()
        let pbxProj = xcodeProj.pbxproj
        let productRef = XCSwiftPackageProductDependency(productName: "MyPackageProduct")
        let dep = PBXTargetDependency(name: nil, product: productRef).add(to: pbxProj)

        try PBXNativeTarget.test(
            name: "App",
            dependencies: [dep],
            productType: .application
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        // When
        let mapped = try mapper.map(dep, xcodeProj: xcodeProj)

        // Then
        #expect(mapped == .package(product: "MyPackageProduct", type: .runtime, condition: nil))
    }

    @Test("Maps native target proxies referencing targets in the same project")
    func proxyNativeTarget() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()

        let pbxProj = xcodeProj.pbxproj
        let project = try #require(pbxProj.rootObject)
        let proxy = PBXContainerItemProxy(
            containerPortal: .project(project),
            remoteGlobalID: .string("GLOBAL_ID"),
            proxyType: .nativeTarget,
            remoteInfo: "NativeTarget"
        )
        .add(to: pbxProj)

        let dep = PBXTargetDependency(name: nil, target: nil, targetProxy: proxy).add(to: pbxProj)

        try PBXNativeTarget.test(
            name: "App",
            dependencies: [dep],
            productType: .application
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        // When
        let mapped = try mapper.map(dep, xcodeProj: xcodeProj)

        // Then
        #expect(mapped == .target(name: "NativeTarget", status: .required, condition: nil))
    }

    @Test("Maps proxy dependencies referencing other projects via file references")
    func proxyProjectReference() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()

        let pbxProj = xcodeProj.pbxproj
        let fileRef = try PBXFileReference.test(path: "TestProject.xcodeproj")
            .add(to: pbxProj)
            .addToMainGroup(in: pbxProj)

        let proxy = PBXContainerItemProxy(
            containerPortal: .fileReference(fileRef),
            remoteGlobalID: .string("GLOBAL_ID"),
            proxyType: .nativeTarget,
            remoteInfo: "OtherTarget"
        ).add(to: pbxProj)

        let dep = PBXTargetDependency(name: nil, target: nil, targetProxy: proxy).add(to: pbxProj)

        try PBXNativeTarget.test(
            name: "App",
            dependencies: [dep],
            productType: .application
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        // When
        let mapped = try mapper.map(dep, xcodeProj: xcodeProj)

        // Then
        let result = try #require(mapped)
        let expectedPath = xcodeProj.projectPath
        #expect(result == .project(target: "OtherTarget", path: expectedPath, status: .required, condition: nil))
    }

    @Test("Maps reference proxies to libraries when file type is a dylib")
    func proxyReferenceProxyLibrary() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()

        let pbxProj = xcodeProj.pbxproj
        let referenceProxy = try PBXReferenceProxy(
            fileType: "compiled.mach-o.dylib",
            path: "libTest.dylib",
            remote: nil,
            sourceTree: .group
        )
        .add(to: pbxProj)
        .addToMainGroup(in: pbxProj)
        let mainGroup = try #require(pbxProj.projects.first?.mainGroup)
        let projectRef = PBXProject.test(
            name: "RemoteProject",
            buildConfigurationList: .test(),
            mainGroup: mainGroup
        ).add(to: pbxProj)

        let proxy = PBXContainerItemProxy(
            containerPortal: .project(projectRef),
            remoteGlobalID: .string("GLOBAL_ID"),
            proxyType: .reference,
            remoteInfo: "SomeRemoteInfo"
        )
        proxy.remoteGlobalID = .object(referenceProxy)

        let dep = PBXTargetDependency(name: nil, target: nil, targetProxy: proxy).add(to: pbxProj)

        try PBXNativeTarget.test(
            name: "App",
            dependencies: [dep],
            productType: .application
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        // When
        let mapped = try mapper.map(dep, xcodeProj: xcodeProj)

        // Then
        let result = try #require(mapped)
        let expectedPath = xcodeProj.srcPath.appending(component: "libTest.dylib")
        let publicHeaders = xcodeProj.srcPath
        #expect(
            result == .library(
                path: expectedPath,
                publicHeaders: publicHeaders,
                swiftModuleMap: nil,
                condition: nil
            )
        )
    }

    @Test("Maps frameworks when encountered as proxy references")
    func proxyReferenceFileFramework() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()

        let pbxProj = xcodeProj.pbxproj
        let fileRef = try PBXFileReference.test(path: "MyLib.framework")
            .add(to: pbxProj)
            .addToMainGroup(in: pbxProj)
        let mainGroup = try #require(pbxProj.projects.first?.mainGroup)

        let projectRef = PBXProject.test(
            name: "RemoteProject",
            buildConfigurationList: .test(),
            mainGroup: mainGroup
        ).add(to: pbxProj)

        let proxy = PBXContainerItemProxy(
            containerPortal: .project(projectRef),
            remoteGlobalID: .object(fileRef),
            proxyType: .reference,
            remoteInfo: "SomeFramework"
        )
        pbxProj.add(object: proxy)

        let dep = PBXTargetDependency(name: nil, target: nil, targetProxy: proxy).add(to: pbxProj)

        try PBXNativeTarget.test(
            name: "App",
            dependencies: [dep],
            productType: .application
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        // When
        let mapped = try mapper.map(dep, xcodeProj: xcodeProj)

        // Then
        let result = try #require(mapped)
        let expectedPath = xcodeProj.srcPath.appending(component: "MyLib.framework")
        #expect(result == .framework(path: expectedPath, status: .required, condition: nil))
    }

    @Test("Maps dependencies with platform filters to conditions")
    func platformConditions() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()

        let pbxProj = xcodeProj.pbxproj
        let target = try PBXNativeTarget.test(
            name: "ConditionalTarget",
            productType: .application
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        let dep = PBXTargetDependency(name: "ConditionalTarget", target: target).add(to: pbxProj)
        dep.platformFilters = ["macos", "ios"]

        try PBXNativeTarget.test(
            name: "App",
            dependencies: [dep],
            productType: .application
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        // When
        let mapped = try mapper.map(dep, xcodeProj: xcodeProj)

        // Then
        let result = try #require(mapped)
        #expect(result == .target(name: "ConditionalTarget", status: .required, condition: .when([.ios, .macos])))
    }

    @Test("Ignores dependencies that cannot be matched to targets, products, or proxies")
    func noMatches() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()

        let pbxProj = xcodeProj.pbxproj
        // A dependency with no target, no product, no proxy.
        let dep = PBXTargetDependency.test(name: nil).add(to: pbxProj)

        try PBXNativeTarget.test(
            name: "App",
            dependencies: [dep],
            productType: .application
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        // When
        #expect(throws: TargetDependencyMappingError.unknownDependencyType(name: "Unknown dependency name")) {
            try mapper.map(dep, xcodeProj: xcodeProj)
        }
    }

    @Test("Maps single-platform filter dependencies correctly")
    func singlePlatformFilter() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()

        let pbxProj = xcodeProj.pbxproj
        let target = try PBXNativeTarget.test(
            name: "SinglePlatform",
            productType: .application
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        let dep = PBXTargetDependency(name: "SinglePlatform", target: target).add(to: pbxProj)
        dep.platformFilter = "tvos"

        try PBXNativeTarget.test(
            name: "App",
            dependencies: [dep],
            productType: .application
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        // When
        let mapped = try mapper.map(dep, xcodeProj: xcodeProj)

        // Then
        #expect(mapped == .target(name: "SinglePlatform", status: .required, condition: .when([.tvos])))
    }

    @Test("Ignores invalid platform filters, mapping dependency without conditions")
    func invalidPlatformFilter() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()

        let pbxProj = xcodeProj.pbxproj
        let target = try PBXNativeTarget.test(
            name: "UnknownPlatform",
            productType: .framework
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        let dep = PBXTargetDependency(name: "UnknownPlatform", target: target).add(to: pbxProj)
        dep.platformFilter = "weirdos"

        try PBXNativeTarget.test(
            name: "App",
            dependencies: [dep],
            productType: .commandLineTool
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        // When
        let mapped = try mapper.map(dep, xcodeProj: xcodeProj)

        // Then
        #expect(mapped == .target(name: "UnknownPlatform", status: .required, condition: nil))
    }
}
