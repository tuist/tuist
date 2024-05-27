import Foundation
import Mockable

@Mockable
protocol UniqueIDGenerating {
    func uniqueID() -> String
}

final class UniqueIDGenerator: UniqueIDGenerating {
    func uniqueID() -> String {
        UUID().uuidString
    }
}
