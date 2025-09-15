@freestanding(expression)
public macro SampleMacro() -> String = #externalMacro(module: "SampleMacroPlugin", type: "SampleMacro")
