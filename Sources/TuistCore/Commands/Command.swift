import Utility

public protocol Command {
    static var command: String { get }
    static var overview: String { get }
    init(parser: ArgumentParser)
    func run(with arguments: ArgumentParser.Result) throws
}

public protocol HiddenCommand {
    static var command: String { get }
    init()
    func run(arguments: [String]) throws
}
