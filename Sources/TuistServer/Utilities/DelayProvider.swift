import Foundation
import Mockable

@Mockable
public protocol DelayProviding {
    func delay(for retry: Int) -> UInt64
}

public struct DelayProvider: DelayProviding {
    public init() {}

    public func delay(for retry: Int) -> UInt64 {
        /// 0.1 seconds
        let baseInterval = TimeInterval(1_000_000)
        let randomInterval = Double.random(in: -1_000_000 ... 1_000_000)
        return UInt64(baseInterval * pow(2, Double(retry)) + randomInterval)
    }
}
