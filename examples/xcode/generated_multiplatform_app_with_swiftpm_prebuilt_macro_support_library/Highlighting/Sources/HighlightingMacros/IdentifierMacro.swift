import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros
import SyntaxHelpers

public enum IdentifierMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in _: some MacroExpansionContext
    ) throws -> ExprSyntax {
        let name = node.arguments.first?.expression.trimmedDescription ?? "\"\""
        return "\(raw: name) + \(literal: identifierText("!"))"
    }
}

@main
struct HighlightingMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        IdentifierMacro.self,
    ]
}
