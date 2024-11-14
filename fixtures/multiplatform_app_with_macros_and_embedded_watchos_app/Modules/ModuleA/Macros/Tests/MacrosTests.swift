import ModuleA
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class APIv3ModelMacroTests: XCTestCase {
    let testMacros: [String: Macro.Type] = [
        "Stringify": StringifyMacro.self,
    ]

    func testStringifyStruct() throws {
        assertMacroExpansion(
            """
            #stringify(1+1)
            """,
            expandedSource: """
            (1+1, "1+1")
            """,
            macros: testMacros
        )
    }
}
