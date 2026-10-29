// Benchmark-only host-local transport. Never included in the fleet runtime.
import Foundation
import Virtualization

private struct ResidentRequest: Decodable {
  let id: UUID
  let action: String
}

private struct ResidentReply: Encodable {
  let id: UUID
  let action: String
  let pid: Int32
  let state: String
  let api_ms: Double
  let error: String?
}

@MainActor
func runResidentBenchmark(_ machine: VZVirtualMachine, directory: URL) async {
  let requestURL = directory.appendingPathComponent("resident-request.json")
  let replyURL = directory.appendingPathComponent("resident-reply.json")
  while !Task.isCancelled {
    do {
      try await Task.sleep(nanoseconds: 5_000_000)
      guard FileManager.default.fileExists(atPath: requestURL.path) else { continue }
      let data = try Data(contentsOf: requestURL)
      try FileManager.default.removeItem(at: requestURL)
      guard data.count <= 1024 else { continue }
      let request = try JSONDecoder().decode(ResidentRequest.self, from: data)
      let start = DispatchTime.now().uptimeNanoseconds
      var failure: String?
      do {
        switch request.action {
        case "pause" where machine.state == .running:
          try await machine.pause()
        case "resume" where machine.state == .paused:
          try await machine.resume()
        case "save" where machine.state == .paused:
          if #available(macOS 14, *) {
            try await machine.saveMachineStateTo(url: directory.appendingPathComponent("state.vzvmsave"))
          } else {
            failure = "save requires macOS 14"
          }
        default:
          failure = "invalid action or VM state"
        }
      } catch {
        failure = String(describing: error)
      }
      let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
      let state = machine.state == .paused ? "paused" : (machine.state == .running ? "running" : "other")
      let reply = ResidentReply(id: request.id, action: request.action, pid: getpid(),
                                state: state, api_ms: elapsed, error: failure)
      try JSONEncoder().encode(reply).write(to: replyURL, options: .atomic)
    } catch is CancellationError {
      return
    } catch {
      // The harness has a bounded timeout and will stop its owned VM on failure.
      fputs("resident benchmark transport: \(error)\n", stderr)
      return
    }
  }
}
