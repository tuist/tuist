import Foundation

// MARK: - Regex

extension String {
    public func matches(pattern: String) -> Bool {
        guard let range = self.range(of: pattern, options: .regularExpression) else {
            return false
        }
        return range == self.range(of: self)
    }
}
