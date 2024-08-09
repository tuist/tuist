import TuistSupportTesting
import XCTest

@testable import TuistKit

final class ImportSourceCodeScannerTests: TuistUnitTestCase {
    var subject: ImportSourceCodeScanner!

    override func setUp() {
        subject = ImportSourceCodeScanner()
    }

    func test_whenObjcCodeWithImports() throws {
        let code = """
        #import <UIKit/UIKit.h>
        #import <A/SomeHeader.h>

        @interface UYLAppDelegate : UIResponder <UIApplicationDelegate>

        @property (strong, nonatomic) UIWindow *window;

        @end
        """
        let imports = try subject.extractImports(from: code, language: .objc)
        XCTAssertEqual(imports, ["UIKit", "A"])
    }

    func test_whenObjcCodeWithOneLineImports() throws {
        let code = """
        @import ModuleA; @import ModuleB;

        @interface UYLAppDelegate : UIResponder <UIApplicationDelegate>

        @property (strong, nonatomic) UIWindow *window;

        @end
        """
        let imports = try subject.extractImports(from: code, language: .objc)
        XCTAssertEqual(imports, ["ModuleA", "ModuleB"])
    }

    func test_whenObjcCodeWithSubmoduleImport() throws {
        let code = """
        @import ModuleA.Submodule;

        @interface UYLAppDelegate : UIResponder <UIApplicationDelegate>

        @property (strong, nonatomic) UIWindow *window;

        @end
        """
        let imports = try subject.extractImports(from: code, language: .objc)
        XCTAssertEqual(imports, ["ModuleA"])
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
        let imports = try subject.extractImports(from: code, language: .objc)
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
        let imports = try subject.extractImports(
            from: code,
            language: .objc
        )
        XCTAssertEqual(imports, ["Foundation", "mach-o", "objc"])
    }

    func test_whenSwiftWithDefaultImport() throws {
        let code = """
        import PackageDescription

        func a() { }
        """
        let imports = try subject.extractImports(
            from: code,
            language: .swift
        )
        XCTAssertEqual(imports, ["PackageDescription"])
    }

    func test_whenSwiftWithOneLineImports() throws {
        let code = """
        import ModuleA; import ModuleB

        func a() { }
        """
        let imports = try subject.extractImports(
            from: code,
            language: .swift
        )
        XCTAssertEqual(imports, ["ModuleA", "ModuleB"])
    }

    func test_whenSwiftWithSubmoduleImport() throws {
        let code = """
        import ModuleC.Submodule

        func a() { }
        """
        let imports = try subject.extractImports(
            from: code,
            language: .swift
        )
        XCTAssertEqual(imports, ["ModuleC"])
    }

    func test_whenSwiftWithTypeImports() throws {
        let code = """
        import struct ModuleA.SomeStruct
        import enum ModuleB.SomeEnum
        import class ModuleC.SomeClass

        func a() { }
        """
        let imports = try subject.extractImports(
            from: code,
            language: .swift
        )
        XCTAssertEqual(imports, ["ModuleA", "ModuleB", "ModuleC"])
    }

    func test_whenSwiftWithIfImport() throws {
        let code = """
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
        let imports = try subject.extractImports(
            from: code,
            language: .swift
        )
        XCTAssertEqual(imports, ["ProjectDescription", "ProjectDescriptionHelpers"])
    }

    func test_whenSwiftWithTestableImport() throws {
        let code = """
            @testable import ProjectDescription
            import ProjectDescriptionHelpers

            let packageSettings = PackageSettings(
                productTypes: [
                    "Alamofire": .framework, // default is .staticFramework
                ]
            )
        """
        let imports = try subject.extractImports(
            from: code,
            language: .swift
        )
        XCTAssertEqual(imports, ["ProjectDescription", "ProjectDescriptionHelpers"])
    }
}
