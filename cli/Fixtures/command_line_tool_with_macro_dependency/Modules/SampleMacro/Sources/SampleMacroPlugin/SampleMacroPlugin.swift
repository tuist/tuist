import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

@main
struct SampleMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        SampleMacro.self,
    ]
}

public struct SampleMacro: ExpressionMacro {
    public static func expansion(
        of _: some FreestandingMacroExpansionSyntax,
        in _: some MacroExpansionContext
    ) throws -> ExprSyntax {
        return "\"Hello from macro!\""
    }
}
