import FormattingMacrosSupport
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

public enum StringifyMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in _: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard let argument = node.arguments.first?.expression else {
            fatalError("compiler bug: the macro does not have any arguments")
        }
        return stringifiedExpression(argument)
    }
}

@main
struct FormattingMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        StringifyMacro.self,
    ]
}
