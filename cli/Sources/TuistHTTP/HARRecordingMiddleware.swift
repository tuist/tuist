import Foundation
import OpenAPIRuntime

#if canImport(TuistHAR)
    import TuistHAR
#endif

public enum HARRecordingMiddlewareFactory {
    public static func middlewares() -> [any ClientMiddleware] {
        // Bench toggle: TUIST_BENCH_LEAN=1 drops the per-request HAR
        // recording (a shared-actor crossing on every request) so an A/B can
        // measure how much of the module-cache pull is instrumentation.
        if ProcessInfo.processInfo.environment["TUIST_BENCH_LEAN"] == "1" {
            return []
        }
        #if canImport(TuistHAR)
            return [TuistHAR.HARRecordingMiddleware()]
        #else
            return []
        #endif
    }
}
