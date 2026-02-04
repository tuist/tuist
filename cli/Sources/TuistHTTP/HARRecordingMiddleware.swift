import Foundation
import OpenAPIRuntime

#if canImport(TuistHAR)
    import TuistHAR
#endif

public enum HARRecordingMiddlewareFactory {
    public static func middlewares() -> [any ClientMiddleware] {
        #if canImport(TuistHAR)
            return [TuistHAR.HARRecordingMiddleware()]
        #else
            return []
        #endif
    }
}
