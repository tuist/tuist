@testable import ModuleAMacros_Testable
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class StringifyMacroTests: XCTestCase {
    let testMacros: [String: Macro.Type] = [
        "stringify": StringifyMacro.self,
    ]

    func testStringifyStruct() throws {
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
