import GRPCCore

enum REAPICapabilityNegotiation {
    /// Allow the gateway's 20-second activation wait plus connection setup on each attempt.
    static func run<Response>(
        _ operation: (CallOptions) async throws -> Response
    ) async throws -> Response {
        var options = CallOptions.defaults
        options.timeout = .seconds(30)
        var retries = 0
        while true {
            try Task.checkCancellation()
            do {
                return try await operation(options)
            } catch let error as RPCError {
                guard retries < 3, [.unavailable, .resourceExhausted].contains(error.code) else { throw error }
                retries += 1
                try await Task.sleep(for: .seconds(2))
            }
        }
    }
}
