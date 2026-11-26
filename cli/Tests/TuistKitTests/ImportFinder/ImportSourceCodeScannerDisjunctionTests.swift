import Testing

@testable import TuistInspectCommand

struct ImportSourceCodeScannerDisjunctionTests {
    private let subject = ImportSourceCodeScanner()

    @Test
    func disjunctionRequiresAtLeastOneModule() {
        let code = """
        #if canImport(FrameworkA)||canImport ( FrameworkB ) || canImport(FrameworkC) // comment
        import Feature
        #endif
        """
        let scannedImports = subject.scanImports(from: code, language: .swift)

        #expect(scannedImports == [
            ScannedImport(module: "Feature", canImportConditions: [
                CanImportCondition(alternatives: [["FrameworkA"], ["FrameworkB"], ["FrameworkC"]]),
            ]),
        ])
        let modules: Set<String> = ["FrameworkA", "FrameworkB", "FrameworkC"]
        #expect(ImportSourceCodeScanner.imports(in: scannedImports, unreachableModules: modules) == [])
        for module in modules {
            #expect(
                ImportSourceCodeScanner.imports(in: scannedImports, unreachableModules: modules.subtracting([module]))
                    == ["Feature"]
            )
        }
        #expect(ImportSourceCodeScanner.imports(in: scannedImports, unreachableModules: nil) == ["Feature"])
    }

    @Test
    func conjunctionHasHigherPrecedenceThanDisjunction() {
        let code = """
        #if canImport(A) || canImport(B) && canImport(C)
        import First
        #endif
        #if canImport(A) && canImport(B) || canImport(C)
        import Second
        #endif
        """
        let scannedImports = subject.scanImports(from: code, language: .swift)
        let cases: [(Set<String>, Set<String>)] = [
            ([], []),
            (["A"], ["First"]),
            (["B"], []),
            (["C"], ["Second"]),
            (["A", "B"], ["First", "Second"]),
            (["A", "C"], ["First", "Second"]),
            (["B", "C"], ["First", "Second"]),
            (["A", "B", "C"], ["First", "Second"]),
        ]

        #expect(scannedImports == [
            ScannedImport(module: "First", canImportConditions: [CanImportCondition(alternatives: [["A"], ["B", "C"]])]),
            ScannedImport(module: "Second", canImportConditions: [CanImportCondition(alternatives: [["A", "B"], ["C"]])]),
        ])
        for (reachableModules, expectedImports) in cases {
            let unreachableModules = Set(["A", "B", "C"]).subtracting(reachableModules)
            #expect(ImportSourceCodeScanner
                .imports(in: scannedImports, unreachableModules: unreachableModules) == expectedImports)
        }
    }

    @Test
    func disjunctionsCombineWithNestedConditionsAndResetForElseBranches() {
        let code = """
        #if canImport(A) || canImport(B)
        #if canImport(C) || canImport(D)
        import Nested
        #elseif canImport(E)
        import ElseIf
        #else
        import Else
        #endif
        #endif
        """
        let scannedImports = subject.scanImports(from: code, language: .swift)

        #expect(scannedImports == [
            ScannedImport(module: "Nested", canImportConditions: [
                CanImportCondition(alternatives: [["A"], ["B"]]),
                CanImportCondition(alternatives: [["C"], ["D"]]),
            ]),
            ScannedImport(module: "ElseIf", canImportConditions: [CanImportCondition(alternatives: [["A"], ["B"]])]),
            ScannedImport(module: "Else", canImportConditions: [CanImportCondition(alternatives: [["A"], ["B"]])]),
        ])
        #expect(ImportSourceCodeScanner.imports(in: scannedImports, unreachableModules: ["A", "C", "E"]) == [
            "Nested",
            "ElseIf",
            "Else",
        ])
        #expect(ImportSourceCodeScanner.imports(in: scannedImports, unreachableModules: ["A", "C", "D", "E"]) == [
            "ElseIf",
            "Else",
        ])
        #expect(ImportSourceCodeScanner.imports(in: scannedImports, unreachableModules: ["A", "B", "C", "E"]) == [])
    }
}
