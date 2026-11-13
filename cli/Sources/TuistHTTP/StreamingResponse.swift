import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A response whose body arrives as the server sends it, for long-lived responses such as ND-JSON log streams. The
/// shared session's 90-second resource timeout would cut those off, so streams use a session that allows an hour
/// (the request timeout still ends a stream that goes quiet).
enum StreamingResponse {
    private static let resourceTimeout: TimeInterval = 3600

    static func start(
        _ request: URLRequest,
        session base: URLSession
    ) async throws -> (URLResponse, AsyncThrowingStream<ArraySlice<UInt8>, any Error>) {
        let configuration = base.configuration
        configuration.timeoutIntervalForResource = resourceTimeout
        #if canImport(FoundationNetworking)
            // FoundationNetworking has no `bytes(for:)`; a data delegate hands the chunks over as they arrive. It also
            // crashes when a session is invalidated after its task ends ("_MultiHandle deallocated with non-zero
            // retain count"), so every stream shares one session that is never invalidated.
            let stream = TaskStream()
            let task = Router.shared.session(configuration: configuration).dataTask(with: request)
            Router.shared.register(task, stream)
            stream.chunks.onTermination = { _ in task.cancel() }
            let response = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    stream.setResponseContinuation(continuation)
                    task.resume()
                }
            } onCancel: {
                task.cancel()
            }
            return (response, stream.stream)
        #else
            let session = URLSession.tuist(configuration: configuration)
            let (bytes, response) = try await session.bytes(for: request)
            let stream = AsyncThrowingStream<ArraySlice<UInt8>, any Error> { continuation in
                // One chunk per line, so a reader sees each log line as soon as it arrives.
                let reader = Task {
                    var line: [UInt8] = []
                    do {
                        for try await byte in bytes {
                            line.append(byte)
                            if byte == UInt8(ascii: "\n") || line.count >= 64 * 1024 {
                                continuation.yield(ArraySlice(line))
                                line.removeAll(keepingCapacity: true)
                            }
                        }
                        if !line.isEmpty { continuation.yield(ArraySlice(line)) }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                    session.finishTasksAndInvalidate()
                }
                continuation.onTermination = { _ in
                    reader.cancel()
                    bytes.task.cancel()
                }
            }
            return (response, stream)
        #endif
    }

    #if canImport(FoundationNetworking)
        /// One stream's response and chunks.
        private final class TaskStream: @unchecked Sendable {
            let stream: AsyncThrowingStream<ArraySlice<UInt8>, any Error>
            let chunks: AsyncThrowingStream<ArraySlice<UInt8>, any Error>.Continuation
            private let lock = NSLock()
            private var responseContinuation: CheckedContinuation<URLResponse, any Error>?

            init() {
                (stream, chunks) = AsyncThrowingStream.makeStream()
            }

            func setResponseContinuation(_ continuation: CheckedContinuation<URLResponse, any Error>) {
                lock.withLock { responseContinuation = continuation }
            }

            func respond(_ response: URLResponse) {
                takeResponseContinuation()?.resume(returning: response)
            }

            func complete(_ error: (any Error)?) {
                if let error {
                    takeResponseContinuation()?.resume(throwing: error)
                    chunks.finish(throwing: error)
                } else {
                    chunks.finish()
                }
            }

            private func takeResponseContinuation() -> CheckedContinuation<URLResponse, any Error>? {
                lock.withLock {
                    defer { responseContinuation = nil }
                    return responseContinuation
                }
            }
        }

        /// The delegate of the shared streaming session, handing each task's events to that task's stream.
        private final class Router: NSObject, URLSessionDataDelegate, @unchecked Sendable {
            static let shared = Router()
            private let lock = NSLock()
            private var session: URLSession?
            private var streams: [Int: TaskStream] = [:]

            /// The shared session, created with the first stream's configuration.
            func session(configuration: URLSessionConfiguration) -> URLSession {
                lock.withLock {
                    if let session { return session }
                    let created = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                    session = created
                    return created
                }
            }

            func register(_ task: URLSessionTask, _ stream: TaskStream) {
                lock.withLock { streams[task.taskIdentifier] = stream }
            }

            private func stream(for task: URLSessionTask, removing: Bool = false) -> TaskStream? {
                lock.withLock { removing ? streams.removeValue(forKey: task.taskIdentifier) : streams[task.taskIdentifier] }
            }

            func urlSession(
                _: URLSession,
                dataTask: URLSessionDataTask,
                didReceive response: URLResponse,
                completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
            ) {
                stream(for: dataTask)?.respond(response)
                completionHandler(.allow)
            }

            func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
                stream(for: dataTask)?.chunks.yield(ArraySlice(data))
            }

            func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
                stream(for: task, removing: true)?.complete(error)
            }
        }
    #endif
}
