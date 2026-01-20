import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import MyMacros_Testable

struct StringifyMacroTests {
    let testMacros: [String: Macro.Type] = [
        "stringify": StringifyMacro.self,
    ]

    @Test func stringifyExpression() throws {
        assertMacroExpansion(
            """
            #stringify(1+1)
            """,
            expandedSource: """
            (1 + 1, "1+1")
            """,
            macros: testMacros
        )
    }
}
