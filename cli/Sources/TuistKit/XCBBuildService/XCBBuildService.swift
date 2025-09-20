import Darwin
import Foundation
import SWBBuildService
import SWBProtocol
import SWBUtil

struct XCBBuildService {
    private typealias FD = Int32

    private func decodeFrames(_ buffer: inout [UInt8], direction: Direction, observer: MessageObserver) -> Int {
        var forwarded = 0
        while buffer.count - forwarded >= 12 {
            let headerStart = forwarded
            let payloadStart = headerStart + 12
            var chLE: UInt64 = 0
            withUnsafeMutableBytes(of: &chLE) { $0.copyBytes(from: buffer[headerStart ..< headerStart + 8]) }
            var szLE: UInt32 = 0
            withUnsafeMutableBytes(of: &szLE) { $0.copyBytes(from: buffer[headerStart + 8 ..< headerStart + 12]) }
            let payloadLen = Int(UInt32(littleEndian: szLE))
            let total = 12 + payloadLen
            if buffer.count - forwarded < total { break }

            let payload = buffer[payloadStart ..< payloadStart + payloadLen]
            do {
                let d = MsgPackDeserializer(ArraySlice(payload))
                let ipc = try IPCMessage(from: d)
                
                // Append to log file instead of calling observer
                let logPath = "/Users/marekfort/Desktop/log.txt"
                let logEntry = """
                    \n[Direction: \(direction), Channel: \(UInt64(littleEndian: chLE)), Length: \(payloadLen), Name: \(type(of: ipc.message).name), Message: \(ipc.message)]
                    """
                
                if let logData = logEntry.data(using: .utf8) {
                    if !FileManager.default.fileExists(atPath: logPath) {
                        FileManager.default.createFile(atPath: logPath, contents: nil)
                    }
                    if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                        defer { fileHandle.closeFile() }
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(logData)
                    }
                }
                
                observer.didDecode(
                    direction: direction,
                    channel: UInt64(littleEndian: chLE),
                    length: payloadLen,
                    name: type(of: ipc.message).name,
                    message: ipc.message,
                    payload: Array(payload)
                )
            } catch {
                observer.didDecodeError(
                    direction: direction,
                    channel: UInt64(littleEndian: chLE),
                    length: payloadLen,
                    error: error
                )
            }
            forwarded += total
        }
        return forwarded
    }

    // MARK: - Helpers

    private func sniffInitialFrameAndAppPath() throws -> (appPath: String?, firstFrame: [UInt8], remainder: [UInt8]) {
        var buf: [UInt8] = []
        var first: [UInt8] = []
        var app: String?
        let chunk = 4096
        let tmp = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { tmp.deallocate() }
        while first.isEmpty {
            let r = read(STDIN_FILENO, tmp, chunk)
            if r < 0 { if errno == EINTR { continue }; throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            if r == 0 { break }
            buf.append(contentsOf: UnsafeBufferPointer(start: tmp, count: r))
            guard buf.count >= 12 else { continue }
            var szLE: UInt32 = 0
            withUnsafeMutableBytes(of: &szLE) { $0.copyBytes(from: buf[8 ..< 12]) }
            let total = 12 + Int(UInt32(littleEndian: szLE))
            if buf.count >= total {
                first = Array(buf[0 ..< total])
                buf.removeFirst(total)
                let payload = Array(first[12 ..< first.count])
                if let ipc = try? IPCMessage(from: MsgPackDeserializer(ArraySlice(payload))),
                   let cs = ipc.message as? CreateSessionRequest
                {
                    let dev = (cs as DeveloperPathTransitional).effectiveDeveloperPath?.str
                    app = dev.flatMap { ($0 as NSString).deletingLastPathComponent } ?? cs.appPath?.str
                }
            }
        }
        return (app, first, buf)
    }

    private func makePipe() throws -> (read: FD, write: FD) {
        var fds: [FD] = [0, 0]
        guard pipe(&fds) == 0 else { throw POSIXError(.EIO) }
        return (fds[0], fds[1])
    }

    private func writeAll(fd: FD, bytes: UnsafePointer<UInt8>, count: Int) throws {
        var written = 0
        while written < count {
            let r = write(fd, bytes.advanced(by: written), count - written)
            if r < 0 { if errno == EINTR { continue }; throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            if r == 0 { throw POSIXError(.EPIPE) }
            written += r
        }
    }

    private func pluginsURL(forXcodeApp appPath: String) -> URL? {
        let rel = "Contents/SharedFrameworks/XCBuild.framework/Versions/A/PlugIns/SWBBuildService.bundle/Contents/PlugIns"
        let full = (appPath as NSString).appendingPathComponent(rel)
        return FileManager.default.fileExists(atPath: full) ? URL(fileURLWithPath: full, isDirectory: true) : nil
    }

    private func launchInProcessService(inputFD: FD, outputFD: FD, pluginsDirectory: URL?) -> Task<Void, Error> {
        Task.detached {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                swiftbuildServiceEntryPoint(inputFD: inputFD, outputFD: outputFD, pluginsDirectory: pluginsDirectory) { err in
                    if let err { cont.resume(throwing: err) } else { cont.resume(returning: ()) }
                }
            }
        }
    }

    private func startPump(readFD: FD, writeFD: FD, direction: Direction, observer: MessageObserver) -> Task<Void, Never> {
        Task.detached { [self] in
            var buffer = [UInt8]()
            let chunk = 64 * 1024
            let tmp = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
            defer { tmp.deallocate() }
            func forward(_ count: Int) {
                buffer.withUnsafeBytes { raw in
                    let p = raw.bindMemory(to: UInt8.self).baseAddress!
                    try? writeAll(fd: writeFD, bytes: p, count: count)
                }
                buffer.removeFirst(count)
            }
            while true {
                let r = read(readFD, tmp, chunk)
                if r < 0 { if errno == EINTR { continue }; break }
                if r == 0 { break }
                buffer.append(contentsOf: UnsafeBufferPointer(start: tmp, count: r))
                let consumed = decodeFrames(&buffer, direction: direction, observer: observer)
                if consumed > 0 { forward(consumed) }
            }
            if !buffer.isEmpty { forward(buffer.count) }
            if writeFD != STDOUT_FILENO { _ = close(writeFD) }
        }
    }

    func run() async throws {
        _ = signal(SIGPIPE, SIG_IGN)
        let (appPath, firstFrame, remainder) = try sniffInitialFrameAndAppPath()
        let (toServiceRead, toServiceWrite) = try makePipe()
        let (fromServiceRead, fromServiceWrite) = try makePipe()
        let observer: MessageObserver = {
//            if let dbPath = ProcessInfo.processInfo.environment["TUIST_XCBBUILDSERVICE_DB_PATH"], dbPath.hasPrefix("/") {
//                if let obs = try? SQLiteObserver(path: dbPath) { return obs }
//            }
            return NoopObserver()
        }()
        // Always run in-process with Xcode's plugins (if available)
        let plugins = appPath.flatMap(pluginsURL(forXcodeApp:))
        let serviceTask = launchInProcessService(inputFD: toServiceRead, outputFD: fromServiceWrite, pluginsDirectory: plugins)
        if !firstFrame.isEmpty {
            firstFrame.withUnsafeBytes { raw in
                let p = raw.bindMemory(to: UInt8.self).baseAddress!
                try? writeAll(fd: toServiceWrite, bytes: p, count: firstFrame.count)
            }
        }
        if !remainder.isEmpty {
            remainder.withUnsafeBytes { raw in
                let p = raw.bindMemory(to: UInt8.self).baseAddress!
                try? writeAll(fd: toServiceWrite, bytes: p, count: remainder.count)
            }
        }
        let inbound = startPump(readFD: STDIN_FILENO, writeFD: toServiceWrite, direction: .xcodeToService, observer: observer)
        let outbound = startPump(readFD: fromServiceRead, writeFD: STDOUT_FILENO, direction: .serviceToXcode, observer: observer)
        try await serviceTask.value
        _ = await inbound.result
        _ = await outbound.result
    }
}
