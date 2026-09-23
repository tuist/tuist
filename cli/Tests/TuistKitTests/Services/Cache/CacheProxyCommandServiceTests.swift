import Foundation
import Testing

@testable import TuistKit

struct CacheProxyCommandServiceTests {
    @Test func spawn_startsTheExecutableWithSIGTERMUnblockedFromAConcurrencyThread() async throws {
        let (callerBlocksSIGTERM, processIdentifier) = try await Task.detached {
            var mask = sigset_t()
            pthread_sigmask(SIG_SETMASK, nil, &mask)
            let processIdentifier = try CacheProxyCommandService.spawn(
                executable: "/bin/sh",
                arguments: ["-c", "kill -TERM $$; exit 0"]
            )
            return (sigismember(&mask, SIGTERM) == 1, processIdentifier)
        }.value

        var status: Int32 = 0
        waitpid(processIdentifier, &status, 0)

        #expect(callerBlocksSIGTERM, "the spawn must run where the proxy's handoff runs, on a thread that blocks SIGTERM")
        #expect(status & 0x7F == SIGTERM, "the child exited with status \(status) instead of being terminated by SIGTERM")
    }
}
