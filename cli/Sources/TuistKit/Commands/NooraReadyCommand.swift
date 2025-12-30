/// This protocol can be conformed by commands to signal that they
/// have been migrated to Noora and therefore UI happens through Noora,
/// and logs through "logger" can be verbose.
protocol NooraReadyCommand {
    ///  When true it indicates that the command outputs the JSON through the Noora().json interface
    var jsonThroughNoora: Bool { get }
}
