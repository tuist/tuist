import Foundation

extension [Double] {
    func average() -> Double {
        reduce(0, +) / Double(count)
    }
}
