import AutomaticModule
import DynamicModule
import Feature
import PromotedModule
import StaticModule
import Testing
import TestOnlyModule
@testable import HostApp

struct HostedPackageTests {
    @Test
    func packageStateIsSharedWithTheHost() {
        #expect(DynamicState.shared === HostState.dynamic)
        #expect(StaticState.shared === HostState.explicitStatic)
        #expect(AutomaticState.shared === HostState.automatic)
        #expect(PromotedState.shared === HostState.promotedAutomatic)
        #expect(Feature.answer == TestSupport.expectedAnswer)

        HostState.explicitStatic.value = 123
        HostState.automatic.value = 456
        HostState.promotedAutomatic.value = 789
        #expect(StaticState.shared.value == 123)
        #expect(AutomaticState.shared.value == 456)
        #expect(PromotedState.shared.value == 789)
    }
}
