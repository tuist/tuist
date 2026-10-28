// Diagnostic of the public API boundary, not an implementation of lazy paging.
import Foundation
import Virtualization

@available(macOS 14, *)
@MainActor
func restoreWithEarlyResumeProbe(_ machine: VZVirtualMachine, from url: URL) async throws {
  let restoration = Task { @MainActor in
    try await machine.restoreMachineStateFrom(url: url)
  }
  // Yield to the restore operation. The record includes the observed state;
  // a run that already completed is not evidence of overlapping execution.
  try await Task.sleep(nanoseconds: 10_000_000)
  var record: [String: Any] = [
    "state_before": String(describing: machine.state),
    "can_resume": machine.canResume,
    "pid": getpid(),
  ]
  do {
    try await machine.resume()
    record["resume_succeeded"] = true
  } catch {
    let e = error as NSError
    record["resume_succeeded"] = false
    record["error_domain"] = e.domain
    record["error_code"] = e.code
    record["error_message"] = e.localizedDescription
  }
  record["state_after"] = String(describing: machine.state)
  let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
  FileHandle.standardError.write(Data("TUIST_EARLY_RESUME_PROBE ".utf8) + data + Data("\n".utf8))
  try await restoration.value
}
