import Testing

@testable import TuistInspectCommand

struct ImportSourceCodeScannerTests {
    private let subject = ImportSourceCodeScanner()

    @Test
    func whenObjcCodeWithImports() throws {
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

    @Test
    func whenObjcCodeWithOneLineImports() throws {
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

    @Test
    func whenObjcCodeWithSubmoduleImport() throws {
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

    @Test
    func whenObjcWithSemanticImports() throws {
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

    @Test
    func whenObjcWithInclude() throws {
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

    @Test
    func whenSwiftWithDefaultImport() throws {
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

    @Test
    func whenSwiftWithDefaultImportWithComment() throws {
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

    @Test
    func whenSwiftWithDefaultImportWithMultilineComment() throws {
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

    @Test
    func whenSwiftWithOneLineImports() throws {
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

    @Test
    func whenSwiftWithOneLineImportsWithComment() throws {
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

    @Test
    func whenSwiftWithOneLineImportsWithOneParticularComment() throws {
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

    @Test
    func whenSwiftWithSubmoduleImport() throws {
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

    @Test
    func whenSwiftWithTypeImports() throws {
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

    @Test
    func whenSwiftWithIfImport() throws {
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

    // MARK: - canImport guards

    @Test
    func canImportGuard_isSkippedWhenModuleNotReachable() throws {
        // When the gated module is a graph module the target can't reach, the entire
        // `#if canImport(X)` branch is dead code at compile time — its imports
        // must not be reported as implicit.
        let code = """
        import Foundation

        #if canImport(FirebaseAppDistribution)
        import FirebaseAppDistribution

        final class Adapter {}
        #endif
        """

        let imports = try subject.extractImports(
            from: code,
            language: .swift,
            unreachableModules: ["FirebaseAppDistribution"]
        )
        #expect(imports == ["Foundation"])
    }

    @Test
    func canImportGuard_isCountedWhenModuleReachable() throws {
        let code = """
        import Foundation

        #if canImport(FirebaseAppDistribution)
        import FirebaseAppDistribution
        #endif
        """

        let imports = try subject.extractImports(from: code, language: .swift, unreachableModules: [])
        #expect(imports == ["Foundation", "FirebaseAppDistribution"])
    }

    @Test
    func nonCanImportConditionStaysActive() throws {
        // Unsupported expressions and custom flags retain the legacy permissive behaviour.
        let code = """
        #if DEBUG
        import DebugOnly
        #endif

        #if Debug || (Live && canImport(FirebaseAppDistribution))
        import FirebaseAppDistribution
        #endif
        """

        #expect(
            try subject.extractImports(
                from: code,
                language: .swift,
                unreachableModules: ["DebugOnly", "FirebaseAppDistribution"]
            ) == ["DebugOnly", "FirebaseAppDistribution"]
        )
    }

    @Test
    func bareImportWithoutGuardIsAlwaysCounted() throws {
        // Imports outside any #if must keep being flagged — the whole point of the
        // implicit-deps check is to catch this case.
        let code = """
        import FirebaseAppDistribution
        """
        #expect(
            try subject.extractImports(
                from: code,
                language: .swift,
                unreachableModules: ["FirebaseAppDistribution"]
            ) == ["FirebaseAppDistribution"]
        )
    }

    @Test
    func nestedCanImportInsideOtherConditionStillEvaluated() throws {
        // The outer #if BETA is unrecognised → active. The inner canImport is the
        // one we actually filter on.
        let code = """
        #if BETA
        #if canImport(FirebaseAppDistribution)
        import FirebaseAppDistribution
        #endif
        #endif
        """

        #expect(
            try subject.extractImports(
                from: code,
                language: .swift,
                unreachableModules: ["FirebaseAppDistribution"]
            ) == []
        )
        #expect(
            try subject.extractImports(from: code, language: .swift, unreachableModules: []) == ["FirebaseAppDistribution"]
        )
    }

    @Test
    func whenSwiftWithTestableImport() throws {
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

    @Test
    func scanImports_recordsCanImportConditionsOfEveryImport() {
        // Given
        let code = """
        import Foundation
        #if canImport(A)
        import B
            #if canImport(C)
            import D
            #endif
        #else
        import E
        #endif
        """

        // When
        let scannedImports = subject.scanImports(from: code, language: .swift)

        // Then
        #expect(scannedImports == [
            ScannedImport(module: "Foundation", canImportConditions: []),
            ScannedImport(module: "B", canImportConditions: [CanImportCondition(alternatives: [["A"]])]),
            ScannedImport(module: "D", canImportConditions: [
                CanImportCondition(alternatives: [["A"]]),
                CanImportCondition(alternatives: [["C"]]),
            ]),
            ScannedImport(module: "E", canImportConditions: []),
        ])
    }

    @Test
    func imports_skipsImportsOfUnreachableCanImportConditions() {
        // Given
        let scannedImports = [
            ScannedImport(module: "Foundation", canImportConditions: []),
            ScannedImport(module: "B", canImportConditions: [CanImportCondition(alternatives: [["A"]])]),
            ScannedImport(module: "D", canImportConditions: [
                CanImportCondition(alternatives: [["A"]]),
                CanImportCondition(alternatives: [["C"]]),
            ]),
        ]

        // When
        let reachableImports = ImportSourceCodeScanner.imports(in: scannedImports, unreachableModules: ["C"])
        let allImports = ImportSourceCodeScanner.imports(in: scannedImports, unreachableModules: nil)

        // Then
        #expect(reachableImports == ["Foundation", "B"])
        #expect(allImports == ["Foundation", "B", "D"])
    }
}
