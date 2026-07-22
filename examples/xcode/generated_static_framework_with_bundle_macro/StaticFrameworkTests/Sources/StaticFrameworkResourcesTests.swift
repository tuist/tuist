import StaticFramework
import XCTest

final class StaticFrameworkResourcesTests: XCTestCase {
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
