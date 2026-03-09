#if os(macOS)
import Foundation
import TuistMachineMetrics
import TuistLogging

struct InsightsStartCommandService {
    func run() async throws {
        Logger.current.debug("Starting machine metrics sampler")
        let sampler = MachineMetricsSampler()
        try await sampler.run()
    }
}
#endif
