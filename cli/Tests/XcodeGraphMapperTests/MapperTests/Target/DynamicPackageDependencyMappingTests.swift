import Foundation
import Path
import Testing
import XcodeGraph
@testable import XcodeGraphMapper

struct DynamicPackageDependencyMappingTests {
    @Test(arguments: [false, true])
    func mapsDynamicHintsToGraphRoles(embedded: Bool) async throws {
        let path: AbsolutePath = "/project"
        let dependency = TargetDependency.package(
            product: "ProductAlias",
            type: embedded ? .runtimeDynamicEmbedded : .runtimeDynamic,
            condition: .when([.ios])
        )
        let result = try await dependency.graphDependency(sourceDirectory: path, target: Target.test())
        let expectedType: GraphDependency.PackageProductType = embedded ? .runtimeDynamicEmbedded : .runtimeDynamic

        #expect(result == .packageProduct(path: path, product: "ProductAlias", type: expectedType))
        #expect(result.isPrecompiledDynamicAndLinkable == embedded)
        #expect(try JSONDecoder().decode(GraphDependency.self, from: JSONEncoder().encode(result)) == result)
    }

    @Test
    func existingRolesAndSerializedValuesRemainUnchanged() async throws {
        let roles: [(TargetDependency.PackageType, GraphDependency.PackageProductType, String)] = [
            (.runtime, .runtime, "runtime package product"),
            (.runtimeEmbedded, .runtimeEmbedded, "runtime embedded package product"),
            (.plugin, .plugin, "plugin package product"),
            (.macro, .macro, "macro package product"),
        ]
        let path: AbsolutePath = "/project"

        for (type, graphType, rawValue) in roles {
            let result = try await TargetDependency.package(product: "ProductAlias", type: type)
                .graphDependency(sourceDirectory: path, target: Target.test())

            #expect(result == .packageProduct(path: path, product: "ProductAlias", type: graphType))
            #expect(graphType.rawValue == rawValue)
            #expect(try JSONDecoder().decode(
                GraphDependency.PackageProductType.self,
                from: Data("\"\(rawValue)\"".utf8)
            ) == graphType)
        }
    }
}
