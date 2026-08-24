import Foundation
import HTTPTypes
import OpenAPIRuntime
import Synchronization
import Testing

@testable import TuistHTTP

struct ArtifactResumeMiddlewareTests {
    private let baseURL = URL(string: "https://cache.tuist.dev")!
    private let operationID = "downloadXcodeArtifact"

    /// An `HTTPBody` that yields `chunks` and then throws, standing in for a
    /// connection that dies partway through the response.
    private func truncatedBody(_ chunks: [Data]) -> HTTPBody {
        HTTPBody(
            AsyncThrowingStream<ArraySlice<UInt8>, any Error> { continuation in
                for chunk in chunks {
                    continuation.yield(ArraySlice(chunk))
                }
                continuation.finish(throwing: TruncatedTransfer())
            },
            length: .unknown
        )
    }

    private struct TruncatedTransfer: Error {}

    /// Call counting that survives being captured by the `@Sendable` closure
    /// the throwing expectations run the middleware inside.
    private final class RangeLog: Sendable {
        private let entries = Mutex<[String?]>([])

        /// Records this attempt's range header and returns the attempt number.
        func record(_ range: String?) -> Int {
            entries.withLock { values in
                values.append(range)
                return values.count
            }
        }

        var values: [String?] { entries.withLock { $0 } }
    }

    private final class Counter: Sendable {
        private let count = Mutex(0)

        func increment() -> Int {
            count.withLock { value in
                value += 1
                return value
            }
        }

        var value: Int { count.withLock { $0 } }
    }

    private func request(method: HTTPRequest.Method = .get) -> HTTPRequest {
        HTTPRequest(method: method, scheme: nil, authority: nil, path: "/api/cache/cas/artifact")
    }

    private func partialResponse(start: Int, end: Int, total: Int) -> HTTPResponse {
        var response = HTTPResponse(status: .init(code: 206))
        response.headerFields[.contentRange] = "bytes \(start)-\(end)/\(total)"
        return response
    }

    @Test func resumes_from_the_byte_offset_it_reached_instead_of_restarting() async throws {
        let subject = ArtifactResumeMiddleware(resumableOperationIDs: [operationID])
        var observedRanges: [String?] = []

        let (response, body) = try await subject.intercept(
            request(),
            body: nil,
            baseURL: baseURL,
            operationID: operationID
        ) { request, _, _ in
            observedRanges.append(request.headerFields[.range])
            if observedRanges.count == 1 {
                return (HTTPResponse(status: 200), truncatedBody([Data("0123".utf8)]))
            }
            return (
                partialResponse(start: 4, end: 9, total: 10),
                HTTPBody(Data("456789".utf8))
            )
        }

        #expect(response.status.code == 200)
        let collected = try await Data(collecting: body!, upTo: .max)
        #expect(String(decoding: collected, as: UTF8.self) == "0123456789")
        // The resume asked only for the bytes it was missing.
        #expect(observedRanges == [nil, "bytes=4-"])
    }

    @Test func resumes_more_than_once_when_a_transfer_keeps_dying() async throws {
        let subject = ArtifactResumeMiddleware(resumableOperationIDs: [operationID])
        var observedRanges: [String?] = []

        let (_, body) = try await subject.intercept(
            request(),
            body: nil,
            baseURL: baseURL,
            operationID: operationID
        ) { request, _, _ in
            observedRanges.append(request.headerFields[.range])
            switch observedRanges.count {
            case 1:
                return (HTTPResponse(status: 200), truncatedBody([Data("012".utf8)]))
            case 2:
                return (
                    partialResponse(start: 3, end: 9, total: 10),
                    truncatedBody([Data("345".utf8)])
                )
            default:
                return (
                    partialResponse(start: 6, end: 9, total: 10),
                    HTTPBody(Data("6789".utf8))
                )
            }
        }

        let collected = try await Data(collecting: body!, upTo: .max)
        #expect(String(decoding: collected, as: UTF8.self) == "0123456789")
        #expect(observedRanges == [nil, "bytes=3-", "bytes=6-"])
    }

    @Test func gives_up_and_rethrows_once_the_resume_attempts_run_out() async throws {
        let subject = ArtifactResumeMiddleware(
            resumableOperationIDs: [operationID],
            maximumResumeAttempts: 2
        )
        let callCount = Counter()

        // The body is assembled inside `intercept`, so an exhausted resume
        // surfaces there rather than when the caller reads the body.
        await #expect(throws: TruncatedTransfer.self) {
            _ = try await subject.intercept(
                request(),
                body: nil,
                baseURL: baseURL,
                operationID: operationID
            ) { _, _, _ in
                let count = callCount.increment()
                if count == 1 {
                    return (HTTPResponse(status: 200), self.truncatedBody([Data("01".utf8)]))
                }
                return (
                    self.partialResponse(start: count, end: 9, total: 10),
                    self.truncatedBody([Data("2".utf8)])
                )
            }
        }

        // The initial attempt plus two resumes, not an unbounded loop.
        #expect(callCount.value == 3)
    }

    /// A 206 that does not start where the transfer stopped would corrupt the
    /// assembled artifact, so the middleware refuses it rather than appending.
    @Test func refuses_a_resumed_response_that_starts_at_the_wrong_offset() async throws {
        let subject = ArtifactResumeMiddleware(resumableOperationIDs: [operationID])

        await #expect(throws: TruncatedTransfer.self) {
            _ = try await subject.intercept(
                request(),
                body: nil,
                baseURL: baseURL,
                operationID: operationID
            ) { request, _, _ in
                if request.headerFields[.range] == nil {
                    return (HTTPResponse(status: 200), self.truncatedBody([Data("0123".utf8)]))
                }
                return (
                    self.partialResponse(start: 0, end: 9, total: 10),
                    HTTPBody(Data("0123456789".utf8))
                )
            }
        }
    }

    /// A server that ignores the `Range` header answers 200 with the whole
    /// artifact. Appending it to the partial bytes would duplicate the head, so
    /// the partial bytes are discarded and the fresh response wins.
    @Test func starts_over_when_the_server_ignores_the_range_header() async throws {
        let subject = ArtifactResumeMiddleware(resumableOperationIDs: [operationID])
        var callCount = 0

        let (_, body) = try await subject.intercept(
            request(),
            body: nil,
            baseURL: baseURL,
            operationID: operationID
        ) { _, _, _ in
            callCount += 1
            if callCount == 1 {
                return (HTTPResponse(status: 200), truncatedBody([Data("0123".utf8)]))
            }
            return (HTTPResponse(status: 200), HTTPBody(Data("0123456789".utf8)))
        }

        let collected = try await Data(collecting: body!, upTo: .max)
        #expect(String(decoding: collected, as: UTF8.self) == "0123456789")
    }

    /// An operation outside the allowlist keeps the streaming body it always
    /// had, so its failure still surfaces where the caller reads it.
    /// Middlewares nest in array order, so resume must sit outside retry for a
    /// ranged follow-up to be retried at all. Composing the two here pins that
    /// relationship: the call site orders an array, and nothing else would
    /// notice if the two entries were swapped.
    @Test func a_resume_that_meets_a_retryable_status_is_retried_rather_than_abandoned() async throws {
        let resume = ArtifactResumeMiddleware(resumableOperationIDs: [operationID])
        let retry = RetryMiddleware(maxRetries: 3, baseDelayMilliseconds: 0)
        let observedRanges = RangeLog()

        // resume(retry(transport)), matching Client+Cache.swift.
        let (_, body) = try await resume.intercept(
            request(),
            body: nil,
            baseURL: baseURL,
            operationID: operationID
        ) { request, body, url in
            try await retry.intercept(
                request,
                body: body,
                baseURL: url,
                operationID: operationID
            ) { request, _, _ in
                let attempt = observedRanges.record(request.headerFields[.range])
                switch attempt {
                case 1:
                    return (HTTPResponse(status: 200), truncatedBody([Data("0123".utf8)]))
                case 2:
                    // The documented shed on the ranged follow-up. Without
                    // retry in the resume path this ends the download.
                    var shed = HTTPResponse(status: .init(code: 503))
                    shed.headerFields[HTTPField.Name("Retry-After")!] = "0"
                    return (shed, HTTPBody(Data()))
                default:
                    return (
                        partialResponse(start: 4, end: 9, total: 10),
                        HTTPBody(Data("456789".utf8))
                    )
                }
            }
        }

        let collected = try await Data(collecting: body!, upTo: .max)
        #expect(String(decoding: collected, as: UTF8.self) == "0123456789")
        // The shed follow-up was retried with the same range, not restarted.
        #expect(observedRanges.values == [nil, "bytes=4-", "bytes=4-"])
    }

    @Test func does_not_resume_an_operation_outside_the_allowlist() async throws {
        let subject = ArtifactResumeMiddleware(resumableOperationIDs: [operationID])
        let callCount = Counter()

        let (_, body) = try await subject.intercept(
            request(),
            body: nil,
            baseURL: baseURL,
            operationID: "someOtherOperation"
        ) { _, _, _ in
            _ = callCount.increment()
            return (HTTPResponse(status: 200), truncatedBody([Data("0123".utf8)]))
        }

        await #expect(throws: TruncatedTransfer.self) {
            _ = try await Data(collecting: body!, upTo: .max)
        }
        #expect(callCount.value == 1)
    }

    /// Error bodies are short JSON the caller decodes verbatim; resuming one
    /// would be meaningless and re-requesting it hides the failure.
    @Test func leaves_a_non_success_response_untouched() async throws {
        let subject = ArtifactResumeMiddleware(resumableOperationIDs: [operationID])
        var callCount = 0

        let (response, _) = try await subject.intercept(
            request(),
            body: nil,
            baseURL: baseURL,
            operationID: operationID
        ) { _, _, _ in
            callCount += 1
            return (HTTPResponse(status: .init(code: 404)), HTTPBody(Data(#"{"message":"gone"}"#.utf8)))
        }

        #expect(response.status.code == 404)
        #expect(callCount == 1)
    }

    @Test func passes_a_complete_response_through_unchanged() async throws {
        let subject = ArtifactResumeMiddleware(resumableOperationIDs: [operationID])
        var callCount = 0

        let (response, body) = try await subject.intercept(
            request(),
            body: nil,
            baseURL: baseURL,
            operationID: operationID
        ) { _, _, _ in
            callCount += 1
            return (HTTPResponse(status: 200), HTTPBody(Data("0123456789".utf8)))
        }

        #expect(response.status.code == 200)
        let collected = try await Data(collecting: body!, upTo: .max)
        #expect(String(decoding: collected, as: UTF8.self) == "0123456789")
        #expect(callCount == 1)
    }

    @Test(arguments: [
        ("bytes 100-199/200", 100),
        ("bytes 0-9/10", 0),
        ("bytes */200", nil),
        ("", nil),
    ])
    func reads_the_first_byte_position_from_a_content_range(value: String, expected: Int?) {
        var response = HTTPResponse(status: .init(code: 206))
        if !value.isEmpty {
            response.headerFields[.contentRange] = value
        }
        #expect(ArtifactResumeMiddleware.partialContentStart(of: response) == expected)
    }
}
