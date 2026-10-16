import Foundation

struct ResolutionTiming {
    @TaskLocal static var isEnabled = false

    private let enabled = Self.isEnabled
    private var start = ContinuousClock.now

    mutating func finish(_ phase: String) {
        let end = ContinuousClock.now
        defer { start = end }
        guard enabled else { return }
        let duration = start.duration(to: end).components
        let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        FileHandle.standardError.write(Data("swifterpm timing \(phase): \(String(format: "%.3f", seconds))s\n".utf8))
    }
}
