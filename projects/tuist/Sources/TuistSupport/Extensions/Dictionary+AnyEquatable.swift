import Foundation

// MARK: - https://stackoverflow.com/a/39170072

public extension Dictionary where Value: Any {
    func isEqual(to otherDict: [Key: Any]) -> Bool {
        NSDictionary(dictionary: self).isEqual(to: NSDictionary(dictionary: otherDict))
    }
}
