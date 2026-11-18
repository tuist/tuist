import SwiftSyntax
import SwiftSyntaxBuilder

public func stringifiedExpression(_ argument: ExprSyntax) -> ExprSyntax {
    "(\(argument), \(literal: argument.trimmedDescription))"
}
