import Foundation

extension TimeZone {
    @TaskLocal static var current: () -> TimeZone = { TimeZone.autoupdatingCurrent }
}
