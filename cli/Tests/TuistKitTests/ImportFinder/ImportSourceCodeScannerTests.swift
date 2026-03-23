import TuistTesting
import Testing

@testable import TuistInspectCommand

struct ImportSourceCodeScannerTests {
    var subject: ImportSourceCodeScanner!

    init() {
        subject = ImportSourceCodeScanner()
    }

    @Test func test_whenObjcCodeWithImports() throws {
        // Given
        let code = """
        #import <UIKit/UIKit.h>
        #import <A/SomeHeader.h>

        @interface UYLAppDelegate : UIResponder <UIApplicationDelegate>

        @property (strong, nonatomic) UIWindow *window;

        @end
        """

        // When
        let imports = try subject.extractImports(from: code, language: .objc)

        // Then
        #expect(imports == ["UIKit", "A"])
    }

    @Test func test_whenObjcCodeWithOneLineImports() throws {
        // Given
        let code = """
        @import ModuleA; @import ModuleB;

        @interface UYLAppDelegate : UIResponder <UIApplicationDelegate>

        @property (strong, nonatomic) UIWindow *window;

        @end
        """

        // When
        let imports = try subject.extractImports(from: code, language: .objc)

        // Then
        #expect(imports == ["ModuleA", "ModuleB"])
    }

    @Test func test_whenObjcCodeWithSubmoduleImport() throws {
        // Given
        let code = """
        @import ModuleA.Submodule;

        @interface UYLAppDelegate : UIResponder <UIApplicationDelegate>

        @property (strong, nonatomic) UIWindow *window;

        @end
        """

        // When
        let imports = try subject.extractImports(from: code, language: .objc)

        // Then
        #expect(imports == ["ModuleA"])
    }

    @Test func test_whenObjcWithSemanticImports() throws {
        // Given
        let code = """
        @import Cocoa ;
        @import LuaSkin;

        #import "ExternalReferences.h"

        #define USERDATA_TAG     "hs.axuielement"
        #define OBSERVER_TAG     "hs.axuielement.observer"
        #define AXTEXTMARKER_TAG "hs.axuielement.axtextmarker"
        #define AXTEXTMRKRNG_TAG "hs.axuielement.axtextmarkerrange"
        """

        // When
        let imports = try subject.extractImports(from: code, language: .objc)

        // Then
        #expect(imports == ["Cocoa", "LuaSkin"])
    }

    @Test func test_whenObjcWithInclude() throws {
        // Given
        let code = """
        #import <Foundation/Foundation.h>
        #include <mach-o/loader.h>
        #include <objc/runtime.h>
        const char **_CFGetProgname(void);
        const char **_CFGetProcessPath(void);
        int _NSGetExecutablePath(char* buf, uint32_t* bufsize);
        """

        // When
        let imports = try subject.extractImports(
            from: code,
            language: .objc
        )

        // Then
        #expect(imports == ["Foundation", "mach-o", "objc"])
    }

    @Test func test_whenSwiftWithDefaultImport() throws {
        // Given
        let code = """
        import PackageDescription

        func a() { }
        """

        // When
        let imports = try subject.extractImports(
            from: code,
            language: .swift
        )

        // Then
        #expect(imports == ["PackageDescription"])
    }

    @Test func test_whenSwiftWithDefaultImportWithComment() throws {
        // Given
        let code = """
        ////        import PackageDescription

        func a() { }
        """

        // When
        let imports = try subject.extractImports(
            from: code,
            language: .swift
        )

        // Then
        #expect(imports == [])
    }

    @Test func test_whenSwiftWithDefaultImportWithMultilineComment() throws {
        // Given
        let code = """
        /*
        import PackageDescription
        */

        func a() { }
        """

        // When
        let imports = try subject.extractImports(
            from: code,
            language: .swift
        )

        // Then
        #expect(imports == [])
    }

    @Test func test_whenSwiftWithOneLineImports() throws {
        // Given
        let code = """
        import ModuleA; import ModuleB

        func a() { }
        """

        // When
        let imports = try subject.extractImports(
            from: code,
            language: .swift
        )

        // Then
        #expect(imports == ["ModuleA", "ModuleB"])
    }

    @Test func test_whenSwiftWithOneLineImportsWithComment() throws {
        // Given
        let code = """
        //// import ModuleA; import ModuleB

        func a() { }
        """

        // When
        let imports = try subject.extractImports(
            from: code,
            language: .swift
        )

        // Then
        #expect(imports == [])
    }

    @Test func test_whenSwiftWithOneLineImportsWithOneParticularComment() throws {
        // Given
        let code = """
        import ModuleA; /* import ModuleB */

        func a() { }
        """

        // When
        let imports = try subject.extractImports(
            from: code,
            language: .swift
        )

        // Then
        #expect(imports == ["ModuleA"])
    }

    @Test func test_whenSwiftWithSubmoduleImport() throws {
        // Given
        let code = """
        import ModuleC.Submodule

        func a() { }
        """

        // When
        let imports = try subject.extractImports(
            from: code,
            language: .swift
        )

        // Then
        #expect(imports == ["ModuleC"])
    }

    @Test func test_whenSwiftWithTypeImports() throws {
        // Given
        let code = """
        import struct ModuleA.SomeStruct
        import enum ModuleB.SomeEnum
        import class ModuleC.SomeClass
        import protocol ModuleD.SomeProtocol
        import func ModuleE.someFunction
        import var ModuleF.someVariable
        import let ModuleG.someConstant
        import typealias ModuleH.SomeTypeAlias

        func a() { }
        """

        // When
        let imports = try subject.extractImports(
            from: code,
            language: .swift
        )

        // Then
        #expect(imports == ["ModuleA", "ModuleB", "ModuleC", "ModuleD", "ModuleE", "ModuleF", "ModuleG", "ModuleH"])
    }

    @Test func test_whenSwiftWithIfImport() throws {
        // Given
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

        // When
        let imports = try subject.extractImports(
            from: code,
            language: .swift
        )

        // Then
        #expect(imports == ["ProjectDescription", "ProjectDescriptionHelpers"])
    }

    @Test func test_whenSwiftWithTestableImport() throws {
        // Given
        let code = """
            @testable import ProjectDescription
            import ProjectDescriptionHelpers

            let packageSettings = PackageSettings(
                productTypes: [
                    "Alamofire": .framework, // default is .staticFramework
                ]
            )
        """

        // When
        let imports = try subject.extractImports(
            from: code,
            language: .swift
        )

        // Then
        #expect(imports == ["ProjectDescription", "ProjectDescriptionHelpers"])
    }
}
