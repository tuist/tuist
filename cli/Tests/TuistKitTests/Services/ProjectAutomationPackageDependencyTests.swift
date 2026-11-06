import Foundation
import ProjectAutomation
import Testing
import XcodeGraph
@testable import TuistKit

struct ProjectAutomationPackageDependencyTests {
    @Test(arguments: [false, true])
    func dynamicHintsPreserveTheExistingAutomationProjection(embedded: Bool) throws {
        let dynamic = XcodeGraph.TargetDependency.package(
            product: "ProductAlias",
            type: embedded ? .runtimeDynamicEmbedded : .runtimeDynamic,
            condition: .when([.ios])
        )
        let legacy = XcodeGraph.TargetDependency.package(
            product: "ProductAlias",
            type: embedded ? .runtimeEmbedded : .runtime,
            condition: .when([.ios])
        )
        let result = ProjectAutomation.Target.from(dynamic)
        let legacyResult = ProjectAutomation.Target.from(legacy)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        #expect(result == .package(product: "ProductAlias", embedded: embedded))
        #expect(result == legacyResult)
        #expect(try encoder.encode(result) == encoder.encode(legacyResult))
    }

    @Test
    func buildTimeProductsKeepTheirAutomationRoles() {
        #expect(ProjectAutomation.Target.from(.package(product: "BuildPlugin", type: .plugin)) ==
            .packagePlugin(product: "BuildPlugin"))
        #expect(ProjectAutomation.Target.from(.package(product: "CompilerMacro", type: .macro)) ==
            .packageMacro(product: "CompilerMacro"))
    }
}
