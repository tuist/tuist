import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

@main
struct ModuleAMacros: CompilerPlugin {
    var providingMacros: [Macro.Type] = [
        StringifyMacro.self,
    ]
}

public struct StringifyMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in _: some MacroExpansionContext
    ) -> ExprSyntax {
        guard let argument = node.arguments.first?.expression else {
            fatalError("compiler bug: the macro does not have any arguments")
        }

        return "(\(argument), \(literal: argument.description))"
    }
}
