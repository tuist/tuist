#if os(macOS)
    import Foundation
    import TuistLogging
    import TuistMachineMetrics

    struct SampleHostMetricsService {
        func run() async throws {
            Logger.current.debug("Starting machine metrics sampler")
            let sampler = MachineMetricsSampler()
            try await sampler.run()
        }
    }
#endif
