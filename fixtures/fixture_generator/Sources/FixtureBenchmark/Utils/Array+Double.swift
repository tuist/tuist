import Foundation

extension Array where Element == Double {
    func average() -> Double {
        return reduce(0, +) / Double(count)
    }
}
