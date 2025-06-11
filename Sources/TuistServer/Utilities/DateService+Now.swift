import Foundation

extension Date {
    @TaskLocal static var now: () -> Date = { Date() }
}
