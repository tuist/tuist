import Testing

struct AtlasPipTests {
    @Test func quickTapsRevealDifferentExpressionsAndBoundIntensity() {
        var pip = AtlasPipReaction()
        let expected: [AtlasPipReaction.Expression] = [.wave, .curious, .delighted, .surprised, .affectionate]
        for (index, expression) in expected.enumerated() {
            pip.activate(at: Double(index) * 0.15)
            #expect(pip.expression == expression)
            #expect(pip.burstCount == index + 1)
        }
        for index in 5..<100 {
            pip.activate(at: Double(index) * 0.15, pressDuration: 2)
        }
        #expect(pip.burstCount == 5)
        #expect(pip.intensity == 1)
    }

    @Test func aPauseStartsANewBurstAndSettlingRestoresNeutral() {
        var pip = AtlasPipReaction()
        pip.activate(at: 1)
        pip.activate(at: 1.1)
        pip.settle()
        #expect(pip.expression == .neutral)
        #expect(pip.intensity == 0)
        pip.activate(at: 2)
        #expect(pip.burstCount == 1)
        #expect(pip.expression == .wave)
        #expect(pip.intensity == 0)
    }

    @Test func slowerGreetingsStillVaryWithoutInventingATapBurst() {
        var pip = AtlasPipReaction()
        pip.activate(at: 1)
        #expect(pip.expression == .wave)
        pip.activate(at: 3)
        #expect(pip.expression == .curious)
        #expect(pip.burstCount == 1)
    }

    @Test(arguments: [
        (0.0, AtlasPipReaction.Expression.wave),
        (0.4, .delighted),
        (0.6, .surprised),
        (0.8, .affectionate)
    ]) func durationChangesTheReactionWithoutPressure(duration: Double, expected: AtlasPipReaction.Expression) {
        var pip = AtlasPipReaction()
        pip.activate(at: 1, pressDuration: duration)
        #expect(pip.expression == expected)
        #expect(pip.intensity == duration)
        #expect(pip.burstCount == 1)
    }

    @Test(arguments: [-1.0, .infinity, .nan]) func invalidDurationIsTreatedAsATap(duration: Double) {
        var pip = AtlasPipReaction()
        pip.activate(at: 1, pressDuration: duration)
        #expect(pip.expression == .wave)
        #expect(pip.intensity == 0)
    }
}
