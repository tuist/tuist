import SyntaxHelpers

@freestanding(expression)
public macro identifier(_ name: String) -> String =
    #externalMacro(module: "HighlightingMacros", type: "IdentifierMacro")

public let highlightedMessage = "\(#identifier("macro")) \(identifierText("runtime"))"
