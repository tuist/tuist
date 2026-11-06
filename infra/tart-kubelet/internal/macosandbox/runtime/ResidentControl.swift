import Foundation
import Virtualization

private struct SandboxRequest: Decodable {
  let id: UUID
  let action: String
  let instance: UUID?
}
private struct SandboxReply: Encodable {
  let id: UUID
  let action: String
  let instance: UUID
  let pid: Int32
  let state: String
  let error: String?
}

// These files live in the host-only VM directory, never in a guest share.
// Each runtime has a fresh instance nonce: an old request cannot mutate a new
// process after a restore or host-service restart.
@MainActor
func runSandboxControl(_ machine: VZVirtualMachine, directory: URL) async {
  let instance = UUID()
  let requestURL = directory.appendingPathComponent("sandbox-request.json")
  let replyURL = directory.appendingPathComponent("sandbox-reply.json")
  while !Task.isCancelled {
    do {
      try await Task.sleep(nanoseconds: 5_000_000)
      guard FileManager.default.fileExists(atPath: requestURL.path) else { continue }
      let data = try Data(contentsOf: requestURL)
      try FileManager.default.removeItem(at: requestURL)
      guard data.count <= 1024 else { continue }
      let request = try JSONDecoder().decode(SandboxRequest.self, from: data)
      var failure: String?
      do {
        if request.action != "status" && request.instance != instance {
          failure = "runtime instance changed"
        } else {
          switch request.action {
          case "status": break
          case "pause" where machine.state == .paused: break
          case "pause" where machine.state == .running: try await machine.pause()
          case "resume" where machine.state == .running || machine.state == .paused:
            // A resident resume can follow a completed save whose process fence
            // failed. Invalidate that checkpoint before the guest can write disk.
            for name in ["state.vzvmsave", "checkpoint-instance"] {
              let file = directory.appendingPathComponent(name)
              if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
              }
            }
            try synchronizeSandboxDirectory(directory)
            if machine.state == .paused { try await machine.resume() }
          case "fence" where machine.state == .paused:
            let marker = try String(contentsOf: directory.appendingPathComponent("checkpoint-instance"), encoding: .utf8)
            guard marker == instance.uuidString && FileManager.default.fileExists(atPath: directory.appendingPathComponent("state.vzvmsave").path) else {
              throw NSError(domain: "TuistSandbox", code: 1)
            }
          case "save" where machine.state == .paused:
            if #available(macOS 14, *) {
              let temporary = directory.appendingPathComponent("state.pending.vzvmsave")
              try? FileManager.default.removeItem(at: temporary)
              try await machine.saveMachineStateTo(url: temporary)
              let handle = try FileHandle(forWritingTo: temporary)
              try handle.synchronize()
              try handle.close()
              let destination = directory.appendingPathComponent("state.vzvmsave")
              if rename(temporary.path, destination.path) != 0 {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
              }
              // A checkpoint marker is written only after Apple's save succeeds.
              try Data(instance.uuidString.utf8).write(to: directory.appendingPathComponent("checkpoint-instance"), options: .atomic)
              let marker = try FileHandle(forWritingTo: directory.appendingPathComponent("checkpoint-instance"))
              try marker.synchronize()
              try marker.close()
              try synchronizeSandboxDirectory(directory)
            } else { failure = "save requires macOS 14" }
          default: failure = "invalid action or VM state"
          }
        }
      } catch { failure = String(describing: error) }
      let state = machine.state == .paused ? "paused" : (machine.state == .running ? "running" : "other")
      let reply = SandboxReply(id: request.id, action: request.action, instance: instance, pid: getpid(), state: state, error: failure)
      try JSONEncoder().encode(reply).write(to: replyURL, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: replyURL.path)
      if request.action == "fence" && failure == nil { Foundation.exit(0) }
    } catch is CancellationError { return }
      catch { fputs("sandbox control failure: \(error)\n", stderr) }
  }
}

func synchronizeSandboxDirectory(_ directory: URL) throws {
  let descriptor = open(directory.path, O_RDONLY)
  guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
  defer { close(descriptor) }
  guard fsync(descriptor) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
