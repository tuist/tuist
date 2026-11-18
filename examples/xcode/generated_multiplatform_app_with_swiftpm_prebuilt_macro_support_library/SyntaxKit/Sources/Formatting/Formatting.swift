@freestanding(expression)
public macro stringify<T>(_ value: T) -> (T, String) =
    #externalMacro(module: "FormattingMacros", type: "StringifyMacro")

public let formattedMessage = #stringify(1 + 2).1
