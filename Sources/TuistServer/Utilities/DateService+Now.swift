import Foundation

extension Date {
    @TaskLocal static var now: () -> Date = { Date(timeIntervalSince1970: 0) }
}
