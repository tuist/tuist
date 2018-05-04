import Foundation

/// Utils class that contains dependencies used by commands.
protocol CommandsContexting: Contexting {}

/// Default commands context that conforms CommandsContexting.
final class CommandsContext: Context, CommandsContexting {}
