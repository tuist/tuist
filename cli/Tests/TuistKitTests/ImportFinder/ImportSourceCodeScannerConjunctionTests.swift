import Testing

@testable import TuistInspectCommand

struct ImportSourceCodeScannerConjunctionTests {
    private let subject = ImportSourceCodeScanner()

    @Test
    func conjunctionRequiresEveryModule() throws {
        let code = """
        #if canImport(FrameworkA) && canImport(FrameworkB)
        import Feature
        #endif
        """
        let scannedImports = subject.scanImports(from: code, language: .swift)

        #expect(scannedImports == [
            ScannedImport(module: "Feature", canImportConditions: [
                CanImportCondition(alternatives: [["FrameworkA", "FrameworkB"]]),
            ]),
        ])
        #expect(ImportSourceCodeScanner.imports(in: scannedImports, unreachableModules: []) == ["Feature"])
        #expect(ImportSourceCodeScanner.imports(in: scannedImports, unreachableModules: ["FrameworkB"]) == [])
        #expect(ImportSourceCodeScanner.imports(in: scannedImports, unreachableModules: ["FrameworkA"]) == [])
        #expect(ImportSourceCodeScanner
            .imports(in: scannedImports, unreachableModules: ["FrameworkA", "FrameworkB"]) == [])
        #expect(ImportSourceCodeScanner.imports(in: scannedImports, unreachableModules: nil) == ["Feature"])
    }

    @Test
    func conjunctionsCombineWithNestedConditionsAndResetForElseBranches() {
        let code = """
        #if canImport(Outer)
        #if canImport ( A )&&canImport(B) && canImport(C) // comment
        import Nested
        #elseif canImport(Other)
        import ElseIf
        #else
        import Else
        #endif
        #endif
        """
        let scannedImports = subject.scanImports(from: code, language: .swift)

        #expect(scannedImports == [
            ScannedImport(module: "Nested", canImportConditions: [
                CanImportCondition(alternatives: [["Outer"]]),
                CanImportCondition(alternatives: [["A", "B", "C"]]),
            ]),
            ScannedImport(module: "ElseIf", canImportConditions: [CanImportCondition(alternatives: [["Outer"]])]),
            ScannedImport(module: "Else", canImportConditions: [CanImportCondition(alternatives: [["Outer"]])]),
        ])
        #expect(ImportSourceCodeScanner.imports(in: scannedImports, unreachableModules: ["C"]) == ["ElseIf", "Else"])
        #expect(ImportSourceCodeScanner.imports(in: scannedImports, unreachableModules: ["Outer", "A", "B", "C"]) == [])
    }

    @Test(arguments: [
        "canImport(A) || DEBUG",
        "canImport(A) && canImport(B) || DEBUG",
        "canImport(A) && DEBUG",
        "canImport(A) && !canImport(B)",
        "(canImport(A) && canImport(B))",
        "canImport(A) || (canImport(B) && canImport(C))",
        "canImport(A) &&",
        "&& canImport(A)",
        "canImport(A) ||",
        "|| canImport(A)",
        "canImport(A) || || canImport(B)",
        "canImport(A) || canImport(B) &&",
    ])
    func unsupportedExpressionsStayActive(condition: String) throws {
        let code = """
        #if \(condition)
        import Feature
        #endif
        """

        #expect(
            try subject.extractImports(from: code, language: .swift, unreachableModules: ["A", "B", "C"]) == ["Feature"]
        )
    }
}
