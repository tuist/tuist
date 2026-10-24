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

    @Test(arguments: [0.0, 0.5, 1.0]) func greetingAnticipatesAndSettlesWithBoundedIndependentJoints(intensity: Double) {
        #expect(AtlasPipMotion.pose(at: 0, intensity: intensity) == .rest)
        let anticipation = AtlasPipMotion.pose(at: 0.1, intensity: intensity)
        let wave = AtlasPipMotion.pose(at: 0.7, intensity: intensity)
        #expect(anticipation.bodyDrop > 0)
        #expect(anticipation.armAngle < AtlasPipPose.rest.armAngle)
        #expect(wave.armAngle > 0)
        #expect(wave.bodyDrop < anticipation.bodyDrop)

        for frame in 0...288 {
            let pose = AtlasPipMotion.pose(at: Double(frame) / 120, intensity: intensity)
            #expect(abs(pose.bodyAngle) <= 3)
            #expect((0...4.1).contains(pose.bodyDrop))
            #expect((-108...22).contains(pose.armAngle))
            #expect(abs(pose.leftFootAngle) <= 1.2)
            #expect(abs(pose.rightFootAngle) <= 1)
            #expect(pose.leftFootAngle == 0 || pose.rightFootAngle == 0)
        }
        #expect(AtlasPipMotion.pose(at: AtlasPipMotion.duration, intensity: intensity) == .rest)
        #expect(AtlasPipMotion.pose(at: 100, intensity: intensity) == .rest)
    }

    @Test func anotherTapContinuesFromTheCurrentJointsRatherThanSnappingToAPose() {
        let current = AtlasPipMotion.pose(at: 0.72, intensity: 0.5)
        #expect(AtlasPipMotion.pose(at: 0, intensity: 1, from: current) == current)
        let next = AtlasPipMotion.pose(at: 0.00001, intensity: 1, from: current)
        #expect(abs(next.armAngle - current.armAngle) < 0.001)
        #expect(abs(next.bodyAngle - current.bodyAngle) < 0.001)
        #expect(abs(next.bodyDrop - current.bodyDrop) < 0.001)
        #expect(abs(next.leftFootAngle - current.leftFootAngle) < 0.001)
        #expect(abs(next.rightFootAngle - current.rightFootAngle) < 0.001)
        #expect(AtlasPipMotion.pose(at: AtlasPipMotion.duration, from: current) == .rest)
    }

    @Test func blinkClosesAndReopensWithoutChangingTheRestingRig() {
        #expect(AtlasPipMotion.eyeOpenness(at: 0) == 1)
        #expect(AtlasPipMotion.eyeOpenness(at: 5.15) == 0)
        #expect(AtlasPipMotion.eyeOpenness(at: 5.6) == 1)
        for frame in 0...672 {
            #expect((0...1).contains(AtlasPipMotion.eyeOpenness(at: Double(frame) / 120)))
        }
        #expect(AtlasPipMotion.pose(at: 5.15) == .rest)
    }

    @Test(arguments: [Double.infinity, -.infinity, .nan]) func invalidMotionTimesRemainStill(time: Double) {
        #expect(AtlasPipMotion.pose(at: time) == .rest)
        #expect(AtlasPipMotion.eyeOpenness(at: time) == 1)
    }
}
