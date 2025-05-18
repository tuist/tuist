import Foundation
import Mockable

@Mockable
protocol DateServicing: Sendable {
    func now() -> Date
}

struct DateService: DateServicing {
    func now() -> Date {
        Date()
    }
}
