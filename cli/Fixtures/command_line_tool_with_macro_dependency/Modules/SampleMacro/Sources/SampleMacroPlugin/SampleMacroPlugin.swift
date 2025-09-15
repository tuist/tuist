import SwiftSyntax
import SwiftSyntaxMacros
import SwiftCompilerPlugin

@main
struct SampleMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
      SampleMacro.self,
    ]
}

public struct SampleMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        return "\"Hello from macro!\""
    }
}
