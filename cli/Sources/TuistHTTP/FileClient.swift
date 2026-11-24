import FileSystem
import Foundation
import Path

#if canImport(TuistHAR)
    import Synchronization
    import TuistHAR
    import TuistLogging
    import TuistSupport
#endif

#if canImport(TuistHAR)
    enum FileClientError: LocalizedError, FatalError, HTTPStatusCodeError {
        case urlSessionError(URLRequest, Error, AbsolutePath?)
        case downloadInterrupted(URLRequest, Error, AbsolutePath, DownloadProgress)
        case serverSideError(URLRequest, HTTPURLResponse, AbsolutePath?)
        case invalidResponse(URLRequest, AbsolutePath?)
        case noLocalURL(URLRequest)

        // MARK: - HTTPStatusCodeError

        var httpStatusCode: Int {
            guard case let .serverSideError(_, response, _) = self else { return 0 }
            return response.statusCode
        }

        /// Only a status the server answered with can make a repeated transfer pointless.
        var isRetryable: Bool {
            guard case .serverSideError = self else { return true }
            return !HTTPRetryPolicy.isPermanentClientError(statusCode: httpStatusCode)
        }

        // MARK: - FatalError

        var description: String {
            switch self {
            case let .urlSessionError(request, error, path):
                return "Received a session error\(pathSubstring(path)) when performing \(request.descriptionForError): \(error.localizedDescription)"
            // The progress leads the message: the server keeps only the first 240 characters of a command's
            // error, and the path and presigned URL that follow are longer than that.
            case let .downloadInterrupted(request, error, path, progress):
                return "Received a session error \(progress)\(pathSubstring(path)) when performing \(request.descriptionForError): \(error.localizedDescription)"
            case let .invalidResponse(request, path):
                return "Received unexpected response from the network when performing \(request.descriptionForError)\(pathSubstring(path))"
            case let .serverSideError(request, response, path):
                return "Received error \(response.statusCode) when performing \(request.descriptionForError)\(pathSubstring(path))"
            case let .noLocalURL(request):
                return "Could not locate on disk the downloaded file after performing \(request.descriptionForError)"
            }
        }

        var type: ErrorType {
            switch self {
            case .urlSessionError: return .bug
            case .downloadInterrupted: return .bug
            case .serverSideError: return .bug
            case .invalidResponse: return .bug
            case .noLocalURL: return .bug
            }
        }

        private func pathSubstring(_ path: AbsolutePath?) -> String {
            guard let path else { return "" }
            return " for file at path \(path.pathString)"
        }

        // MARK: - LocalizedError

        var errorDescription: String? { description }
    }

    /// How much of a body a failed download attempt left in its partial file.
    struct DownloadProgress: CustomStringConvertible {
        /// The bytes in the partial file, including the ones earlier attempts left there.
        var bytesOnDisk: Int64
        /// The bytes this attempt received.
        var bytesThisAttempt: Int64
        /// The size of the whole object, or nil when the server did not say.
        var bytesExpected: Int64?

        /// Megabytes with one decimal, formatted without the locale so the message reads the same on every host.
        var description: String {
            guard bytesOnDisk > 0 else { return "before receiving any data" }
            let total = bytesExpected.map { " of \(Self.megabytes($0))" } ?? ""
            let attempt = bytesThisAttempt == bytesOnDisk ? "" : " (\(Self.megabytes(bytesThisAttempt)) MB in this attempt)"
            return "after downloading \(Self.megabytes(bytesOnDisk))\(total) MB\(attempt)"
        }

        private static func megabytes(_ bytes: Int64) -> String {
            String(format: "%.1f", Double(bytes) / 1_000_000)
        }
    }

    public protocol FileClienting {
        func upload(file: AbsolutePath, hash: String, to url: URL) async throws -> Bool
        func download(url: URL, to destination: AbsolutePath) async throws
        /// Downloads a large object as concurrent byte ranges over separate connections, resuming each range on
        /// the next call for the same URL and destination. Falls back to `download(url:to:)` when the server
        /// does not serve ranges of an unchanged object.
        func downloadInParallel(url: URL, to destination: AbsolutePath) async throws
    }

    public struct FileClient: FileClienting {
        // MARK: - Attributes

        private let session: URLSession?
        private let fileSystem: FileSysteming
        private let partialDownloads = PartialDownloads()
        private let parallelDownloads = ParallelDownloads()
        private let parallelRangeSize: Int64
        private let successStatusCodeRange = 200 ..< 300

        /// The most byte ranges of one download in flight at once, each on its own connection.
        static let parallelRangeLanes = 8

        // MARK: - Init

        public init(
            session: URLSession? = nil,
            fileSystem: FileSysteming = FileSystem(),
            parallelRangeSize: Int64 = 8 * 1024 * 1024
        ) {
            self.session = session
            self.fileSystem = fileSystem
            self.parallelRangeSize = parallelRangeSize
        }

        // MARK: - Public

        /// The body is written to `<destination>.partial` as it arrives. When an attempt fails, the bytes it
        /// received stay there, and the next call for the same URL and destination on this client asks only for
        /// the rest (`Range`, guarded by `If-Range` with the first response's validator). A server that answers
        /// with the whole object, or with a range that does not continue the file, restarts it from zero.
        public func download(url: URL, to destination: AbsolutePath) async throws {
            let partialPath = destination.parentDirectory.appending(component: "\(destination.basename).partial")
            let session = resolvedSession()
            if let validator = partialDownloads.validator(url: url, destination: destination),
               let size = try? await fileSystem.fileMetadata(at: partialPath)?.size, size > 0,
               try await attemptDownload(
                   url: url, to: destination, partialPath: partialPath,
                   resumingFrom: Int64(size), validator: validator, session: session
               )
            {
                return
            }
            try await attemptDownload(
                url: url, to: destination, partialPath: partialPath, resumingFrom: 0, validator: nil, session: session
            )
        }

        /// A first request for the object's leading `parallelRangeSize` bytes learns its size and validator, then
        /// the rest is split into up to `parallelRangeLanes` ranges fetched at once into `<destination>.partial`,
        /// each `If-Range`-guarded and checked against the first validator (Tigris ignores `If-Range`). When an
        /// attempt fails, the next call for the same URL and destination on this client asks each range only for
        /// the bytes it did not receive. A server that ignores ranges, or an object that changed, restarts the
        /// download through `download(url:to:)`.
        public func downloadInParallel(url: URL, to destination: AbsolutePath) async throws {
            let partialPath = destination.parentDirectory.appending(component: "\(destination.basename).partial")
            var plan: ParallelDownloads.Plan
            if let resumable = parallelDownloads.plan(url: url, destination: destination),
               (try? await fileSystem.exists(partialPath)) == true
            {
                plan = resumable
            } else {
                parallelDownloads.forget(destination: destination)
                guard let probed = try await probeParallelDownload(url: url, to: destination, partialPath: partialPath)
                else {
                    try? await fileSystem.remove(partialPath)
                    return try await download(url: url, to: destination)
                }
                plan = probed
            }

            let session = session
            let validator = plan.validator
            let pending = plan.segments.indices.filter { plan.segments[$0].remaining > 0 }
            let segments = plan.segments
            let outcomes = await withTaskGroup(of: (Int, RangeOutcome).self) { group in
                for (lane, index) in pending.enumerated() {
                    let segment = segments[index]
                    group.addTask {
                        let request = Self.rangeRequest(
                            url: url, from: segment.start + segment.written, to: segment.end, validator: validator
                        )
                        let writer = RangeWriter(
                            path: partialPath, offset: segment.start + segment.written, validator: validator
                        )
                        let laneSession = session ?? .tuistLargeTransfer(lane: lane)
                        return (index, await Self.fetch(request, with: writer, session: laneSession))
                    }
                }
                var outcomes: [(Int, RangeOutcome)] = []
                for await outcome in group {
                    outcomes.append(outcome)
                }
                return outcomes.sorted { $0.0 < $1.0 }
            }

            var bytesThisAttempt: Int64 = 0
            var failure: Error?
            for (index, outcome) in outcomes {
                plan.segments[index].written += outcome.bytesWritten
                bytesThisAttempt += outcome.bytesWritten
                switch outcome {
                case .completed:
                    break
                case .notRanged:
                    parallelDownloads.forget(destination: destination)
                    try? await fileSystem.remove(partialPath)
                    return try await download(url: url, to: destination)
                case let .serverSideError(request, response):
                    // A status decides whether retrying can help, so it wins over a transport failure.
                    failure = FileClientError.serverSideError(request, response, nil)
                case let .failed(request, error, _):
                    if failure == nil {
                        failure = FileClientError.downloadInterrupted(request, error, destination, DownloadProgress(
                            bytesOnDisk: 0, bytesThisAttempt: 0, bytesExpected: plan.total
                        ))
                    }
                }
            }

            if failure == nil, plan.segments.contains(where: { $0.remaining > 0 }) {
                failure = URLError(.networkConnectionLost)
            }
            guard let failure else {
                parallelDownloads.forget(destination: destination)
                try await fileSystem.move(from: partialPath, to: destination)
                return
            }
            parallelDownloads.remember(url: url, destination: destination, plan: plan)
            let progress = DownloadProgress(
                bytesOnDisk: plan.segments.reduce(0) { $0 + $1.written },
                bytesThisAttempt: bytesThisAttempt,
                bytesExpected: plan.total
            )
            switch failure {
            case let FileClientError.downloadInterrupted(request, error, path, _):
                throw FileClientError.downloadInterrupted(request, error, path, progress)
            case let error as FileClientError:
                throw error
            default:
                throw FileClientError.downloadInterrupted(URLRequest(url: url), failure, destination, progress)
            }
        }

        public func upload(file: AbsolutePath, hash _: String, to url: URL) async throws -> Bool {
            guard let metadata = try await fileSystem.fileMetadata(at: file) else {
                throw FileClientError.noLocalURL(URLRequest(url: url))
            }
            let fileSize = UInt64(metadata.size)
            let fileData = try Data(contentsOf: file.url)
            let request = uploadRequest(url: url, fileSize: fileSize, data: fileData)
            let session = resolvedSession()
            do {
                let (_, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    let error = FileClientError.invalidResponse(request, file)
                    HARRecorder.recordDetached { recorder in
                        await Self.recordUploadError(
                            request: request,
                            error: error,
                            requestBodySize: Int(fileSize),
                            recorder: recorder
                        )
                    }
                    throw error
                }
                HARRecorder.recordDetached { recorder in
                    await Self.recordUpload(
                        request: request,
                        response: httpResponse,
                        requestBodySize: Int(fileSize),
                        recorder: recorder
                    )
                }
                if successStatusCodeRange.contains(httpResponse.statusCode) {
                    return true
                } else {
                    throw FileClientError.serverSideError(request, httpResponse, file)
                }
            } catch let error as FileClientError {
                throw error
            } catch {
                HARRecorder.recordDetached { recorder in
                    await Self.recordUploadError(
                        request: request,
                        error: error,
                        requestBodySize: Int(fileSize),
                        recorder: recorder
                    )
                }
                throw FileClientError.urlSessionError(request, error, file)
            }
        }

        // MARK: - Private

        /// Fetches the object's leading bytes into a new partial file and plans the remaining ranges. Returns nil
        /// when the server did not answer with a range of a validated object of known size.
        private func probeParallelDownload(
            url: URL,
            to destination: AbsolutePath,
            partialPath: AbsolutePath
        ) async throws -> ParallelDownloads.Plan? {
            FileManager.default.createFile(atPath: partialPath.pathString, contents: nil)
            let request = Self.rangeRequest(url: url, from: 0, to: parallelRangeSize - 1, validator: nil)
            let writer = RangeWriter(path: partialPath, offset: 0, validator: nil)
            let outcome = await Self.fetch(request, with: writer, session: session ?? .tuistLargeTransfer(lane: 0))
            let plan = writer.object.map { object in
                ParallelDownloads.Plan(
                    validator: object.validator,
                    total: object.total,
                    segments: Self.segments(
                        total: object.total,
                        firstEnd: object.end,
                        firstWritten: outcome.bytesWritten,
                        rangeSize: parallelRangeSize
                    )
                )
            }
            switch outcome {
            case .completed:
                return plan
            case .notRanged:
                return nil
            case let .serverSideError(request, response):
                try? await fileSystem.remove(partialPath)
                throw FileClientError.serverSideError(request, response, nil)
            case let .failed(request, error, bytesWritten):
                if let plan {
                    parallelDownloads.remember(url: url, destination: destination, plan: plan)
                } else {
                    try? await fileSystem.remove(partialPath)
                }
                throw FileClientError.downloadInterrupted(request, error, destination, DownloadProgress(
                    bytesOnDisk: bytesWritten, bytesThisAttempt: bytesWritten, bytesExpected: plan?.total
                ))
            }
        }

        /// The probed leading range, then the rest of the object split evenly over at most `parallelRangeLanes`
        /// ranges of at least about `rangeSize` bytes.
        static func segments(total: Int64, firstEnd: Int64, firstWritten: Int64, rangeSize: Int64) -> [DownloadSegment] {
            var segments = [DownloadSegment(start: 0, end: firstEnd, written: firstWritten)]
            let rest = total - firstEnd - 1
            guard rest > 0 else { return segments }
            let count = min(Int64(parallelRangeLanes), max(1, rest / max(rangeSize, 1)))
            let size = (rest + count - 1) / count
            var start = firstEnd + 1
            while start < total {
                let end = min(start + size, total) - 1
                segments.append(DownloadSegment(start: start, end: end))
                start = end + 1
            }
            return segments
        }

        private static func rangeRequest(url: URL, from start: Int64, to end: Int64, validator: String?) -> URLRequest {
            var request = URLRequest(url: url)
            request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
            if let validator {
                request.setValue(validator, forHTTPHeaderField: "If-Range")
            }
            return request
        }

        private static func fetch(_ request: URLRequest, with writer: RangeWriter, session: URLSession) async -> RangeOutcome {
            let result: RangeWriter.Result
            do {
                result = try await writer.run(request, session: session)
            } catch {
                HARRecorder.recordDetached { recorder in
                    await Self.recordDownloadError(request: request, error: error, recorder: recorder)
                }
                return .failed(request, error, bytesWritten: writer.bytesWritten)
            }
            if let response = writer.response {
                HARRecorder.recordDetached { recorder in
                    await Self.recordDownload(request: request, response: response, recorder: recorder)
                }
            }
            switch result {
            case .completed:
                return .completed(bytesWritten: writer.bytesWritten)
            case .notRanged:
                return .notRanged
            case let .serverSideError(response):
                return .serverSideError(request, response)
            }
        }

        /// Returns false when the server did not continue the partial file, which is then discarded.
        @discardableResult
        private func attemptDownload(
            url: URL,
            to destination: AbsolutePath,
            partialPath: AbsolutePath,
            resumingFrom offset: Int64,
            validator: String?,
            session: URLSession
        ) async throws -> Bool {
            var rangeRequest = URLRequest(url: url)
            if let validator {
                rangeRequest.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
                rangeRequest.setValue(validator, forHTTPHeaderField: "If-Range")
            }
            let request = rangeRequest
            let writer = PartialFileWriter(path: partialPath, resumeOffset: offset, validator: validator)
            let result: PartialFileWriter.Result
            do {
                result = try await writer.run(request, session: session)
            } catch {
                if let fileValidator = writer.fileValidator, (try? await fileSystem.exists(partialPath)) == true {
                    partialDownloads.remember(url: url, destination: destination, validator: fileValidator)
                } else {
                    partialDownloads.forget(destination: destination)
                    try? await fileSystem.remove(partialPath)
                }
                HARRecorder.recordDetached { recorder in
                    await Self.recordDownloadError(request: request, error: error, recorder: recorder)
                }
                throw FileClientError.downloadInterrupted(request, error, destination, writer.progress)
            }

            if let response = result.response {
                HARRecorder.recordDetached { recorder in
                    await Self.recordDownload(request: request, response: response, recorder: recorder)
                }
            }
            switch result {
            case .completed:
                partialDownloads.forget(destination: destination)
                try await fileSystem.move(from: partialPath, to: destination)
                return true
            case .rangeNotContinued:
                partialDownloads.forget(destination: destination)
                try? await fileSystem.remove(partialPath)
                return false
            case let .serverSideError(response):
                throw FileClientError.serverSideError(request, response, nil)
            case .invalidResponse:
                let error = FileClientError.invalidResponse(request, nil)
                HARRecorder.recordDetached { recorder in
                    await Self.recordDownloadError(request: request, error: error, recorder: recorder)
                }
                throw error
            }
        }

        private func uploadRequest(url: URL, fileSize: UInt64, data: Data) -> URLRequest {
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("application/zip", forHTTPHeaderField: "Content-Type")
            request.setValue(String(fileSize), forHTTPHeaderField: "Content-Length")
            request.setValue("zip", forHTTPHeaderField: "Content-Encoding")
            request.httpBody = data
            return request
        }

        private func resolvedSession() -> URLSession {
            session ?? .tuistLargeTransfer
        }

        // MARK: - HAR Recording

        private static func recordDownload(request: URLRequest, response: HTTPURLResponse, recorder: HARRecorder) async {
            guard let url = request.url else { return }
            let metadata = await retrieveHARMetadata(for: url)
            await recorder.recordRequest(
                request: request,
                response: response,
                requestBody: nil,
                responseBody: nil,
                startTime: metadata.startTime,
                endTime: metadata.endTime,
                timings: metadata.timings,
                httpVersion: metadata.httpVersion,
                requestHeadersSize: metadata.requestHeadersSize,
                responseHeadersSize: metadata.responseHeadersSize
            )
        }

        private static func recordDownloadError(request: URLRequest, error: Error, recorder: HARRecorder) async {
            guard let url = request.url else { return }
            let metadata = await retrieveHARMetadata(for: url)
            await recorder.recordError(
                request: request,
                error: error,
                requestBody: nil,
                startTime: metadata.startTime,
                endTime: metadata.endTime,
                timings: metadata.timings,
                httpVersion: metadata.httpVersion,
                requestHeadersSize: metadata.requestHeadersSize
            )
        }

        private static func recordUpload(
            request: URLRequest,
            response: HTTPURLResponse,
            requestBodySize: Int,
            recorder: HARRecorder
        ) async {
            guard let url = request.url else { return }
            let metadata = await retrieveHARMetadata(for: url)
            await recorder.recordRequest(
                request: request,
                response: response,
                requestBody: nil,
                responseBody: nil,
                startTime: metadata.startTime,
                endTime: metadata.endTime,
                timings: metadata.timings,
                httpVersion: metadata.httpVersion,
                requestHeadersSize: metadata.requestHeadersSize,
                responseHeadersSize: metadata.responseHeadersSize,
                requestBodySize: requestBodySize
            )
        }

        private static func recordUploadError(
            request: URLRequest,
            error: Error,
            requestBodySize: Int,
            recorder: HARRecorder
        ) async {
            guard let url = request.url else { return }
            let metadata = await retrieveHARMetadata(for: url)
            await recorder.recordError(
                request: request,
                error: error,
                requestBody: nil,
                startTime: metadata.startTime,
                endTime: metadata.endTime,
                timings: metadata.timings,
                httpVersion: metadata.httpVersion,
                requestHeadersSize: metadata.requestHeadersSize,
                requestBodySize: requestBodySize
            )
        }

        private struct HARMetadataResult {
            let timings: HAR.Timings?
            let startTime: Date
            let endTime: Date
            let httpVersion: String?
            let requestHeadersSize: Int?
            let responseHeadersSize: Int?
        }

        private static func retrieveHARMetadata(for url: URL) async -> HARMetadataResult {
            guard let metrics = await URLSessionMetricsDelegate.shared.retrieveMetrics(for: url),
                  let harMetadata = URLSessionMetricsDelegate.extractHARMetadata(from: metrics)
            else {
                let now = Date()
                return HARMetadataResult(
                    timings: nil,
                    startTime: now,
                    endTime: now,
                    httpVersion: nil,
                    requestHeadersSize: nil,
                    responseHeadersSize: nil
                )
            }
            return HARMetadataResult(
                timings: harMetadata.timings,
                startTime: harMetadata.startTime,
                endTime: harMetadata.endTime,
                httpVersion: harMetadata.httpVersion,
                requestHeadersSize: harMetadata.requestHeadersSize,
                responseHeadersSize: harMetadata.responseHeadersSize
            )
        }
    }

    /// The validators of downloads that failed with bytes left in their partial file, by destination.
    private final class PartialDownloads: Sendable {
        private struct Entry {
            let url: URL
            let validator: String
        }

        private let entries = Mutex<[AbsolutePath: Entry]>([:])

        func validator(url: URL, destination: AbsolutePath) -> String? {
            entries.withLock { entries in
                entries[destination].flatMap { $0.url == url ? $0.validator : nil }
            }
        }

        func remember(url: URL, destination: AbsolutePath, validator: String) {
            entries.withLock { $0[destination] = Entry(url: url, validator: validator) }
        }

        func forget(destination: AbsolutePath) {
            _ = entries.withLock { $0.removeValue(forKey: destination) }
        }
    }

    /// One byte range of a parallel download, `start` through `end` inclusive.
    struct DownloadSegment: Equatable, Sendable {
        let start: Int64
        let end: Int64
        /// The bytes from `start` already in the partial file.
        var written: Int64 = 0

        var remaining: Int64 {
            end - start + 1 - written
        }
    }

    /// The ranges of parallel downloads that failed with bytes left in their partial file, by destination.
    private final class ParallelDownloads: Sendable {
        struct Plan: Sendable {
            let validator: String
            let total: Int64
            var segments: [DownloadSegment]
        }

        private struct Entry {
            let url: URL
            let plan: Plan
        }

        private let entries = Mutex<[AbsolutePath: Entry]>([:])

        func plan(url: URL, destination: AbsolutePath) -> Plan? {
            entries.withLock { entries in
                entries[destination].flatMap { $0.url == url ? $0.plan : nil }
            }
        }

        func remember(url: URL, destination: AbsolutePath, plan: Plan) {
            entries.withLock { $0[destination] = Entry(url: url, plan: plan) }
        }

        func forget(destination: AbsolutePath) {
            _ = entries.withLock { $0.removeValue(forKey: destination) }
        }
    }

    private enum RangeOutcome: @unchecked Sendable {
        case completed(bytesWritten: Int64)
        /// The server answered with the whole object, a 416, or a range of a different object.
        case notRanged
        case serverSideError(URLRequest, HTTPURLResponse)
        case failed(URLRequest, Error, bytesWritten: Int64)

        var bytesWritten: Int64 {
            switch self {
            case let .completed(bytesWritten), let .failed(_, _, bytesWritten): return bytesWritten
            case .notRanged, .serverSideError: return 0
            }
        }
    }

    /// Writes one 206 body into its own region of a shared partial file, from `offset`, as it arrives. Other
    /// writers fill other regions of the same file at the same time, so it never truncates the file.
    private final class RangeWriter: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        enum Result {
            case completed
            case notRanged
            case serverSideError(HTTPURLResponse)
        }

        struct Object {
            let start: Int64
            let end: Int64
            let total: Int64
            let validator: String
        }

        private let path: AbsolutePath
        private let offset: Int64
        /// The validator the range must carry, or nil for the first range, which learns it.
        private let validator: String?
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Result, Error>?
        private var handle: FileHandle?
        private var earlyResult: Result?
        private var writeError: Error?
        private var _bytesWritten: Int64 = 0
        private var _object: Object?
        private var _response: HTTPURLResponse?

        var bytesWritten: Int64 {
            lock.withLock { _bytesWritten }
        }

        /// The object the accepted 206 described.
        var object: Object? {
            lock.withLock { _object }
        }

        var response: HTTPURLResponse? {
            lock.withLock { _response }
        }

        init(path: AbsolutePath, offset: Int64, validator: String?) {
            self.path = path
            self.offset = offset
            self.validator = validator
        }

        func run(_ request: URLRequest, session: URLSession) async throws -> Result {
            let task = session.dataTask(with: request)
            task.delegate = self
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    lock.withLock { self.continuation = continuation }
                    task.resume()
                }
            } onCancel: {
                task.cancel()
            }
        }

        func urlSession(
            _: URLSession,
            dataTask _: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            guard let response = response as? HTTPURLResponse else {
                earlyResult = .notRanged
                return completionHandler(.cancel)
            }
            lock.withLock { _response = response }
            let statusCode = response.statusCode
            guard (200 ..< 300).contains(statusCode) || statusCode == 416 else {
                earlyResult = .serverSideError(response)
                return completionHandler(.cancel)
            }
            // Compares the 206's own validator: Tigris ignores `If-Range` and answers 206 for a changed object.
            guard statusCode == 206, let object = Self.object(of: response), object.start == offset,
                  validator == nil || object.validator == validator
            else {
                earlyResult = .notRanged
                return completionHandler(.cancel)
            }
            do {
                let handle = try FileHandle(forWritingTo: path.url)
                try handle.seek(toOffset: UInt64(offset))
                self.handle = handle
                lock.withLock { _object = object }
                completionHandler(.allow)
            } catch {
                writeError = error
                completionHandler(.cancel)
            }
        }

        func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            do {
                try handle?.write(contentsOf: data)
                lock.withLock { _bytesWritten += Int64(data.count) }
            } catch {
                writeError = error
                dataTask.cancel()
            }
        }

        func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
            try? handle?.close()
            let continuation = lock.withLock {
                defer { self.continuation = nil }
                return self.continuation
            }
            if let earlyResult {
                continuation?.resume(returning: earlyResult)
            } else if let error = writeError ?? error {
                continuation?.resume(throwing: error)
            } else {
                continuation?.resume(returning: .completed)
            }
        }

        /// `Content-Range: bytes <start>-<end>/<size>` of an unencoded body with a validator.
        private static func object(of response: HTTPURLResponse) -> Object? {
            guard let validator = PartialFileWriter.validator(of: response),
                  let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
                  contentRange.hasPrefix("bytes ")
            else { return nil }
            let parts = contentRange.dropFirst("bytes ".count).split(separator: "/")
            guard parts.count == 2, let total = Int64(parts[1]) else { return nil }
            let bounds = parts[0].split(separator: "-")
            guard bounds.count == 2, let start = Int64(bounds[0]), let end = Int64(bounds[1]), end < total
            else { return nil }
            return Object(start: start, end: end, total: total, validator: validator)
        }
    }

    /// Writes one response body to a file as it arrives, so the bytes of a failed transfer stay on disk. Its
    /// delegate methods run on the session's serial delegate queue.
    private final class PartialFileWriter: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        enum Result {
            case completed(HTTPURLResponse)
            /// A 416, or a 206 that does not continue the file from `resumeOffset` with the same validator.
            case rangeNotContinued(HTTPURLResponse)
            case serverSideError(HTTPURLResponse)
            case invalidResponse

            var response: HTTPURLResponse? {
                switch self {
                case let .completed(response), let .rangeNotContinued(response), let .serverSideError(response):
                    return response
                case .invalidResponse:
                    return nil
                }
            }
        }

        private let path: AbsolutePath
        private let resumeOffset: Int64
        private let validator: String?
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Result, Error>?
        private var handle: FileHandle?
        private var earlyResult: Result?
        private var writeError: Error?
        private var _fileValidator: String?
        /// Until a response replaces the file, it still holds what earlier attempts left.
        private var _progress: DownloadProgress

        /// The validator of the object whose bytes are in the file, or nil when they cannot be resumed.
        var fileValidator: String? {
            lock.withLock { _fileValidator }
        }

        var progress: DownloadProgress {
            lock.withLock { _progress }
        }

        init(path: AbsolutePath, resumeOffset: Int64, validator: String?) {
            self.path = path
            self.resumeOffset = resumeOffset
            self.validator = validator
            _fileValidator = validator
            _progress = DownloadProgress(bytesOnDisk: resumeOffset, bytesThisAttempt: 0, bytesExpected: nil)
        }

        func run(_ request: URLRequest, session: URLSession) async throws -> Result {
            let task = session.dataTask(with: request)
            task.delegate = self
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    lock.withLock { self.continuation = continuation }
                    task.resume()
                }
            } onCancel: {
                task.cancel()
            }
        }

        func urlSession(
            _: URLSession,
            dataTask _: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            guard let response = response as? HTTPURLResponse else {
                earlyResult = .invalidResponse
                return completionHandler(.cancel)
            }
            let statusCode = response.statusCode
            guard (200 ..< 300).contains(statusCode) || (statusCode == 416 && resumeOffset > 0) else {
                earlyResult = .serverSideError(response)
                return completionHandler(.cancel)
            }
            let appends = resumeOffset > 0 && statusCode == 206
            if resumeOffset > 0, statusCode == 416 || appends && !continues(response) {
                earlyResult = .rangeNotContinued(response)
                return completionHandler(.cancel)
            }
            do {
                if appends {
                    let handle = try FileHandle(forWritingTo: path.url)
                    try handle.truncate(atOffset: UInt64(resumeOffset))
                    try handle.seek(toOffset: UInt64(resumeOffset))
                    self.handle = handle
                    lock.withLock { _progress.bytesExpected = Self.completeLength(of: response) }
                } else {
                    FileManager.default.createFile(atPath: path.pathString, contents: nil)
                    handle = try FileHandle(forWritingTo: path.url)
                    lock.withLock {
                        _fileValidator = Self.validator(of: response)
                        let length = response.expectedContentLength
                        _progress = DownloadProgress(
                            bytesOnDisk: 0, bytesThisAttempt: 0, bytesExpected: length > 0 ? length : nil
                        )
                    }
                }
                completionHandler(.allow)
            } catch {
                writeError = error
                completionHandler(.cancel)
            }
        }

        func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            do {
                try handle?.write(contentsOf: data)
                lock.withLock {
                    _progress.bytesOnDisk += Int64(data.count)
                    _progress.bytesThisAttempt += Int64(data.count)
                }
            } catch {
                writeError = error
                dataTask.cancel()
            }
        }

        func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            try? handle?.close()
            let continuation = lock.withLock {
                defer { self.continuation = nil }
                return self.continuation
            }
            if let earlyResult {
                continuation?.resume(returning: earlyResult)
            } else if let error = writeError ?? error {
                continuation?.resume(throwing: error)
            } else if let response = task.response as? HTTPURLResponse {
                continuation?.resume(returning: .completed(response))
            } else {
                continuation?.resume(returning: .invalidResponse)
            }
        }

        /// Compares the 206's own validator, not only its start: Tigris, which stores shard artifacts, ignores `If-Range`
        /// and answers a range with 206 even after the object changed.
        private func continues(_ response: HTTPURLResponse) -> Bool {
            guard let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
                  contentRange.hasPrefix("bytes "),
                  let start = contentRange.dropFirst("bytes ".count).split(separator: "-").first.flatMap({ Int64($0) })
            else { return false }
            return start == resumeOffset && Self.validator(of: response) == validator
        }

        /// The object's size from `Content-Range: bytes <start>-<end>/<size>`, or nil when it is `*` or missing.
        private static func completeLength(of response: HTTPURLResponse) -> Int64? {
            response.value(forHTTPHeaderField: "Content-Range")?.split(separator: "/").last.flatMap { Int64($0) }
        }

        /// A strong `ETag`, else `Last-Modified`, the forms `If-Range` accepts. A body URLSession decompressed has
        /// no validator: its byte offsets are not the ones the server's ranges count.
        static func validator(of response: HTTPURLResponse) -> String? {
            let encoding = response.value(forHTTPHeaderField: "Content-Encoding")?.lowercased()
            if let encoding, ["gzip", "x-gzip", "deflate", "br"].contains(encoding) { return nil }
            if let etag = response.value(forHTTPHeaderField: "ETag"), !etag.hasPrefix("W/") { return etag }
            return response.value(forHTTPHeaderField: "Last-Modified")
        }
    }
#endif // canImport(TuistHAR)
