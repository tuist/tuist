import StaticFramework
import Testing

struct StaticFrameworkResourcesTests {
    @Test func implicitBundleDefaultArgument_resolvesResource() {
        #expect(StaticFrameworkAssets.implicitBundleResourceURL() != nil)
    }

    @Test func directBundleMacro_resolvesResource() {
        #expect(StaticFrameworkAssets.directBundleMacroResourceURL() != nil)
    }

    @Test func explicitModule_resolvesResource() {
        #expect(StaticFrameworkAssets.explicitModuleResourceURL() != nil)
    }
}
