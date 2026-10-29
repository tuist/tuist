#if canImport(Security)
    import Foundation
    import HTTPTypes
    import Testing
    import TuistEnvironment
    import TuistEnvironmentTesting
    import TuistTestSupport

    @testable import TuistHTTP

    @Suite(.serialized)
    struct CertificateTrustLiveTests {
        @Test(.withMockedEnvironment(), .enabled(if: ProcessInfo.processInfo.environment["TUIST_TRUST_LIVE"] == "1"))
        func actual_transport_rejects_public_controls_even_with_affected_additional_anchors() async throws {
            let environment = try #require(Environment.mocked)
            let path = TestPaths.fixturesDirectory.appending(components: "CertificateTrust", "issuer-roots.pem")
            environment.variables["TUIST_CA_CERTIFICATE"] = path.pathString
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 30
            let session = URLSession.tuist(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let transport = TuistURLSessionTransport(session: session)
            for issuer in ["emudhra", "aaa-emudhra"] {
                for prefix in ["dv-g3b", "dv-g3c", "ov-g3b", "ov-g3c", "ev-g3b", "ev-g3c"] {
                    let host = "\(prefix)-\(issuer).we-have-a-problem.com"
                    let url = try #require(URL(string: "https://\(host)"))
                    do {
                        _ = try await transport.send(
                            .init(method: .get, scheme: "https", authority: host, path: "/"),
                            body: nil,
                            baseURL: url,
                            operationID: "publicCertificateControl"
                        )
                        Issue.record("Accepted public negative TLS control: \(host)")
                    } catch {
                        let error = error as NSError
                        #expect(error.domain == NSURLErrorDomain)
                        #expect(
                            [NSURLErrorCancelled, NSURLErrorServerCertificateUntrusted].contains(error.code),
                            "Expected certificate rejection, not a network/protocol/timeout failure: \(error)"
                        )
                    }
                }
            }
            let url = try #require(URL(string: "https://letsencrypt.org"))
            let (response, _) = try await transport.send(
                .init(method: .get, scheme: "https", authority: "letsencrypt.org", path: "/"),
                body: nil,
                baseURL: url,
                operationID: "unrelatedPositiveControl"
            )
            #expect(response.status == .ok)
        }
    }
#endif
