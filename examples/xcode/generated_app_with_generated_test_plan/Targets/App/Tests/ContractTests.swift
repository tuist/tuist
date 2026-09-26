import Foundation
import Testing

extension Tag {
    @Tag static var contract: Self
}

@Test(.tags(.contract)) func contract_twoPlusTwo_isFour() {
    #expect(2 + 2 == 4)
}
