@freestanding(expression)
public macro stringify<T>(_ value: T) -> (T, String) =
    #externalMacro(module: "MacroDependencyMacros", type: "StringifyMacro")

public let prebuiltMessage = #stringify("Prebuilt SwiftSyntax").1
