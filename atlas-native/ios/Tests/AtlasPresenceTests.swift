import Foundation
import Testing

@MainActor
struct AtlasPresenceTests {
    @Test func backgroundDuringOpenClosesTheLateConnection() async {
        let started = AsyncStream<Void>.makeStream()
        var finish: CheckedContinuation<Data, Never>?
        var closed = false
        let model = AtlasPresence { action in
            if action["action"] as? String == "open" {
                return await withCheckedContinuation { finish = $0; started.continuation.yield(()) }
            }
            #expect(action["action"] as? String == "close")
            #expect(action["connection"] as? String == "fixture-connection")
            closed = true
            return Data("{\"closed\":true}".utf8)
        }
        model.setActive(true)
        for await _ in started.stream { break }
        model.setActive(false)
        finish?.resume(returning: Data("{\"connection\":\"fixture-connection\"}".utf8))
        await model.stop()
        #expect(closed && model.people.isEmpty)
    }
}
