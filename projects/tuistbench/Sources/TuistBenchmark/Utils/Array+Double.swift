import Foundation

extension Array where Element == Double {
    func average() -> Double {
        reduce(0, +) / Double(count)
    }
}
