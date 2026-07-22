import StaticFramework
import XCTest

/// Exercises StaticFramework's #bundle expansions from a consumer that links the framework
/// as a product, so when StaticFramework is consumed as a cached binary the expansion frozen
/// into the artifact is what resolves at runtime.
final class AppResourcesTests: XCTestCase {
    func test_implicitBundleDefaultArgument_resolvesResource() {
        XCTAssertNotNil(StaticFrameworkAssets.implicitBundleResourceURL())
    }

    func test_directBundleMacro_resolvesResource() {
        XCTAssertNotNil(StaticFrameworkAssets.directBundleMacroResourceURL())
    }

    func test_explicitModule_resolvesResource() {
        XCTAssertNotNil(StaticFrameworkAssets.explicitModuleResourceURL())
    }
}
