import Foundation

// MARK: - https://stackoverflow.com/a/39170072

#if canImport(Darwin)
    extension Dictionary where Value: Any {
        public func isEqual(to otherDict: [Key: Any]) -> Bool {
            NSDictionary(dictionary: self).isEqual(to: NSDictionary(dictionary: otherDict))
        }
    }
#else
    extension Dictionary where Key: Hashable, Value: Any {
        public func isEqual(to otherDict: [Key: Any]) -> Bool {
            guard count == otherDict.count else { return false }
            for (key, value) in self {
                guard let otherValue = otherDict[key] else { return false }
                guard "\(value)" == "\(otherValue)" else { return false }
            }
            return true
        }
    }
#endif
