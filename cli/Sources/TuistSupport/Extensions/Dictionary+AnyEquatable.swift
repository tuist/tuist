import Foundation

// MARK: - https://stackoverflow.com/a/39170072

extension Dictionary where Value: Any {
    public func isEqual(to otherDict: [Key: Any]) -> Bool {
        NSDictionary(dictionary: self).isEqual(to: NSDictionary(dictionary: otherDict))
    }
}
