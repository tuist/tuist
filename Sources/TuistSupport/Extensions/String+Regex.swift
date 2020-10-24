import Foundation

// MARK: - Regex

public extension String {
    func matches(pattern: String) -> Bool {
        guard let range = self.range(of: pattern, options: .regularExpression) else {
            return false
        }
        return range == self.range(of: self)
    }
}
