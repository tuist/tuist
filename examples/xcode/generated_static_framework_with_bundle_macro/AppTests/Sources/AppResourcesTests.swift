import StaticFramework
import Testing

/// Exercises StaticFramework's #bundle expansions from a consumer that links the framework
/// as a product, so when StaticFramework is consumed as a cached binary the expansion frozen
/// into the artifact is what resolves at runtime.
struct AppResourcesTests {
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
