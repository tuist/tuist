@_exported import Logging

extension Logger {
    @TaskLocal public static var current: Logger = .init(label: "dev.tuist.logger")
}
