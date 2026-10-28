import ArgumentParser

protocol XcodeBuildPassthroughCommand: AsyncParsableCommand {
    var passthroughXcodebuildArguments: [String] { get }
    var xcodebuildActionIndex: Int { get set }
}

extension XcodeBuildPassthroughCommand {
    var xcodebuildArguments: [String] {
        var arguments = passthroughXcodebuildArguments
        arguments.insert(Self.configuration.commandName!, at: xcodebuildActionIndex)
        return arguments
    }
}
