#if canImport(Darwin)
    import Foundation
    import HTTPTypes
    import OpenAPIRuntime
    import Testing

    @testable import TuistServer

    struct ServerClientRequestCompressionMiddlewareTests {
        private let subject = ServerClientRequestCompressionMiddleware()
        private let url = URL(string: "https://tuist.dev")!
        private let request = HTTPRequest(
            method: .post,
            scheme: "https",
            authority: "tuist.dev",
            path: "/api/projects/tuist/tuist/tests"
        )
        private let largeBody = Data(String(repeating: "{\"line_numbers\":[1,2,3]}", count: 100_000).utf8)

        @Test func compresses_a_large_create_test_body() async throws {
            var sent: [(HTTPRequest, Data)] = []

            _ = try await subject
                .intercept(request, body: HTTPBody(largeBody), baseURL: url, operationID: "createTest") { request, body, _ in
                    sent.append((request, try await Data(collecting: body!, upTo: .max)))
                    return (HTTPResponse(status: .ok), nil)
                }

            #expect(sent.count == 1)
            #expect(sent[0].0.headerFields[.contentEncoding] == "deflate")
            #expect(sent[0].1.count < largeBody.count / 10)
            #expect(try (sent[0].1 as NSData).decompressed(using: .zlib) as Data == largeBody)
        }

        @Test func sends_the_uncompressed_body_again_when_the_server_cannot_parse_it() async throws {
            var sent: [HTTPRequest] = []

            let (response, _) = try await subject.intercept(
                request,
                body: HTTPBody(largeBody),
                baseURL: url,
                operationID: "createTest"
            ) { request, body, _ in
                sent.append(request)
                _ = try await Data(collecting: body!, upTo: .max)
                return (HTTPResponse(status: sent.count == 1 ? .badRequest : .ok), nil)
            }

            #expect(sent.map { $0.headerFields[.contentEncoding] } == ["deflate", nil])
            #expect(response.status == .ok)
        }

        @Test func leaves_small_bodies_and_other_operations_alone() async throws {
            for (body, operationID) in [(Data("{}".utf8), "createTest"), (largeBody, "createCommandEvent")] {
                var encoding: String?
                _ = try await subject
                    .intercept(request, body: HTTPBody(body), baseURL: url, operationID: operationID) { request, _, _ in
                        encoding = request.headerFields[.contentEncoding]
                        return (HTTPResponse(status: .ok), nil)
                    }
                #expect(encoding == nil)
            }
        }
    }
#endif
