import Foundation

struct ResolutionTiming {
    @TaskLocal static var isEnabled = false

    let enabled: Bool
    private var start = ContinuousClock.now

    init(enabled: Bool) {
        self.enabled = enabled
    }

    mutating func finish(_ phase: String) {
        let end = ContinuousClock.now
        defer { start = end }
        guard enabled else { return }
        let duration = start.duration(to: end).components
        let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        FileHandle.standardError.write(Data(String(format: "swifterpm timing %@: %.3fs\n", phase, seconds).utf8))
    }
}
