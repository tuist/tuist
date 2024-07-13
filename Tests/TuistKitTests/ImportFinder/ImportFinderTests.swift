import TuistSupportTesting
import XCTest

@testable import TuistKit

final class ImportFinderTests: TuistUnitTestCase {
    func test_whenObjcCodeWithImports() throws {
        let code = """
        #import <UIKit/UIKit.h>
        #import <A/SomeHeader.h>

        @interface UYLAppDelegate : UIResponder <UIApplicationDelegate>

        @property (strong, nonatomic) UIWindow *window;

        @end
        """
        let imports = try ImportSourceCodeScanner().extractImports(from: code, language: .objc)
        XCTAssertEqual(imports, ["UIKit", "A"])
    }

    func test_whenObjcWithSemanticImports() throws {
        let code = """
        @import Cocoa ;
        @import LuaSkin;

        #import "ExternalReferences.h"

        #define USERDATA_TAG     "hs.axuielement"
        #define OBSERVER_TAG     "hs.axuielement.observer"
        #define AXTEXTMARKER_TAG "hs.axuielement.axtextmarker"
        #define AXTEXTMRKRNG_TAG "hs.axuielement.axtextmarkerrange"
        """
        let imports = try ImportSourceCodeScanner().extractImports(from: code, language: .objc)
        XCTAssertEqual(imports, ["Cocoa", "LuaSkin"])
    }

    func test_whenObjcWithInclude() throws {
        let code = """
        #import <Foundation/Foundation.h>
        #include <mach-o/loader.h>
        #include <objc/runtime.h>
        const char **_CFGetProgname(void);
        const char **_CFGetProcessPath(void);
        int _NSGetExecutablePath(char* buf, uint32_t* bufsize);
        """
        let imports = try ImportSourceCodeScanner().extractImports(
            from: code,
            language: .objc
        )
        XCTAssertEqual(imports, ["Foundation", "mach-o", "objc"])
    }

    func test_whenSwiftWithImport() throws {
        let code = """
        import PackageDescription

        #if TUIST
            import ProjectDescription
            import ProjectDescriptionHelpers

            let packageSettings = PackageSettings(
                productTypes: [
                    "Alamofire": .framework, // default is .staticFramework
                ]
            )
        #endif
        """
        let imports = try ImportSourceCodeScanner().extractImports(
            from: code,
            language: .swift
        )
        XCTAssertEqual(imports, ["PackageDescription", "ProjectDescription", "ProjectDescriptionHelpers"])
    }
}
