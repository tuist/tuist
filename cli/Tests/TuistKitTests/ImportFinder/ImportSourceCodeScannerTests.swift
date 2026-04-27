import TuistTesting
import XCTest

@testable import TuistInspectCommand

final class ImportSourceCodeScannerTests: TuistUnitTestCase {
    var subject: ImportSourceCodeScanner!

    override func setUp() {
        subject = ImportSourceCodeScanner()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_whenObjcCodeWithImports() throws {
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
        XCTAssertEqual(imports, ["UIKit", "A"])
    }

    func test_whenObjcCodeWithOneLineImports() throws {
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
        XCTAssertEqual(imports, ["ModuleA", "ModuleB"])
    }

    func test_whenObjcCodeWithSubmoduleImport() throws {
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
        XCTAssertEqual(imports, ["ModuleA"])
    }

    func test_whenObjcWithSemanticImports() throws {
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
        XCTAssertEqual(imports, ["Cocoa", "LuaSkin"])
    }

    func test_whenObjcWithInclude() throws {
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
        XCTAssertEqual(imports, ["Foundation", "mach-o", "objc"])
    }

    func test_whenSwiftWithDefaultImport() throws {
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
        XCTAssertEqual(imports, ["PackageDescription"])
    }

    func test_whenSwiftWithDefaultImportWithComment() throws {
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
        XCTAssertEqual(imports, [])
    }

    func test_whenSwiftWithDefaultImportWithMultilineComment() throws {
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
        XCTAssertEqual(imports, [])
    }

    func test_whenSwiftWithOneLineImports() throws {
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
        XCTAssertEqual(imports, ["ModuleA", "ModuleB"])
    }

    func test_whenSwiftWithOneLineImportsWithComment() throws {
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
        XCTAssertEqual(imports, [])
    }

    func test_whenSwiftWithOneLineImportsWithOneParticularComment() throws {
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
        XCTAssertEqual(imports, ["ModuleA"])
    }

    func test_whenSwiftWithSubmoduleImport() throws {
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
        XCTAssertEqual(imports, ["ModuleC"])
    }

    func test_whenSwiftWithTypeImports() throws {
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
        XCTAssertEqual(imports, ["ModuleA", "ModuleB", "ModuleC", "ModuleD", "ModuleE", "ModuleF", "ModuleG", "ModuleH"])
    }

    func test_whenSwiftWithIfImport() throws {
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
        XCTAssertEqual(imports, ["ProjectDescription", "ProjectDescriptionHelpers"])
    }

    // MARK: - Conditional compilation

    func test_canImportImport_isSkippedWhenModuleNotReachable() throws {
        // Mirrors Tarek's FirebaseAppDistributionAdapter.swift on the variants that
        // don't link Firebase: the import should be treated as dead code, not implicit.
        let code = """
        import Foundation

        #if canImport(FirebaseAppDistribution)
        import FirebaseAppDistribution

        final class Adapter {}
        #endif
        """

        let context = CompilationConditionContext(
            flagSetsPerConfiguration: [[]],
            reachableModules: []
        )

        let imports = try subject.extractImports(from: code, language: .swift, context: context)
        XCTAssertEqual(imports, ["Foundation"])
    }

    func test_canImportImport_isCountedWhenModuleReachable() throws {
        let code = """
        import Foundation

        #if canImport(FirebaseAppDistribution)
        import FirebaseAppDistribution
        #endif
        """

        let context = CompilationConditionContext(
            flagSetsPerConfiguration: [[]],
            reachableModules: ["FirebaseAppDistribution"]
        )

        let imports = try subject.extractImports(from: code, language: .swift, context: context)
        XCTAssertEqual(imports, ["Foundation", "FirebaseAppDistribution"])
    }

    func test_compoundExpression_releaseVariantSkipsConditionalImport() throws {
        // `release` variant: no Debug, no Live, no Firebase. Branch must be dead.
        let code = """
        #if Debug || (Live && canImport(FirebaseAppDistribution))
        import FirebaseAppDistribution
        #endif
        """

        let context = CompilationConditionContext(
            flagSetsPerConfiguration: [[]],
            reachableModules: []
        )

        let imports = try subject.extractImports(from: code, language: .swift, context: context)
        XCTAssertEqual(imports, [])
    }

    func test_compoundExpression_betaVariantCountsImport() throws {
        // `beta` variant: Live flag (release config) and Firebase declared.
        let code = """
        #if Debug || (Live && canImport(FirebaseAppDistribution))
        import FirebaseAppDistribution
        #endif
        """

        let context = CompilationConditionContext(
            flagSetsPerConfiguration: [["Debug"], ["Live"]],
            reachableModules: ["FirebaseAppDistribution"]
        )

        let imports = try subject.extractImports(from: code, language: .swift, context: context)
        XCTAssertEqual(imports, ["FirebaseAppDistribution"])
    }

    func test_elseifBranchOnlyTakenWhenPreviousBranchesFalse() throws {
        let code = """
        #if BETA
        import BetaOnly
        #elseif DEBUG
        import DebugOnly
        #else
        import ReleaseOnly
        #endif
        """

        let debugContext = CompilationConditionContext(flagSetsPerConfiguration: [["DEBUG"]])
        XCTAssertEqual(
            try subject.extractImports(from: code, language: .swift, context: debugContext),
            ["DebugOnly"]
        )

        let releaseContext = CompilationConditionContext(flagSetsPerConfiguration: [[]])
        XCTAssertEqual(
            try subject.extractImports(from: code, language: .swift, context: releaseContext),
            ["ReleaseOnly"]
        )

        let betaContext = CompilationConditionContext(flagSetsPerConfiguration: [["BETA"]])
        XCTAssertEqual(
            try subject.extractImports(from: code, language: .swift, context: betaContext),
            ["BetaOnly"]
        )
    }

    func test_nestedConditionalsRequireAllParentsActive() throws {
        let code = """
        #if BETA
        #if canImport(FirebaseAppDistribution)
        import FirebaseAppDistribution
        #endif
        #endif
        """

        // Beta + module reachable → import live.
        let betaWithModule = CompilationConditionContext(
            flagSetsPerConfiguration: [["BETA"]],
            reachableModules: ["FirebaseAppDistribution"]
        )
        XCTAssertEqual(
            try subject.extractImports(from: code, language: .swift, context: betaWithModule),
            ["FirebaseAppDistribution"]
        )

        // Beta but module not reachable → inner #if false → dead.
        let betaWithoutModule = CompilationConditionContext(
            flagSetsPerConfiguration: [["BETA"]],
            reachableModules: []
        )
        XCTAssertEqual(
            try subject.extractImports(from: code, language: .swift, context: betaWithoutModule),
            []
        )

        // Module reachable but BETA flag missing → outer #if false → dead.
        let nonBetaWithModule = CompilationConditionContext(
            flagSetsPerConfiguration: [[]],
            reachableModules: ["FirebaseAppDistribution"]
        )
        XCTAssertEqual(
            try subject.extractImports(from: code, language: .swift, context: nonBetaWithModule),
            []
        )
    }

    func test_bareImportWithoutGuardIsAlwaysCounted() throws {
        // Sanity check: imports outside any #if must keep being flagged. The whole
        // point of the implicit-deps check is to catch this case — we can't
        // accidentally over-correct.
        let code = """
        import FirebaseAppDistribution
        """
        let context = CompilationConditionContext(reachableModules: [])
        XCTAssertEqual(
            try subject.extractImports(from: code, language: .swift, context: context),
            ["FirebaseAppDistribution"]
        )
    }

    func test_unparseableConditionFallsBackToActive() throws {
        // If we ever hit a directive we don't understand, default to "branch active"
        // so the linter keeps surfacing real issues instead of silently dropping them.
        let code = """
        #if some_future_directive(weirdness)
        import SomeModule
        #endif
        """
        let context = CompilationConditionContext()
        XCTAssertEqual(
            try subject.extractImports(from: code, language: .swift, context: context),
            ["SomeModule"]
        )
    }

    func test_whenSwiftWithTestableImport() throws {
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
        XCTAssertEqual(imports, ["ProjectDescription", "ProjectDescriptionHelpers"])
    }
}
