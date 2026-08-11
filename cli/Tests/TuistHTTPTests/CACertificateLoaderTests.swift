#if os(macOS)
    import Foundation
    import Security
    import Testing

    @testable import TuistHTTP

    @Suite
    struct CACertificateLoaderTests {
        private static let caPEM = """
        -----BEGIN CERTIFICATE-----
        MIIC1jCCAb6gAwIBAgIJAJlwwm+UwR8bMA0GCSqGSIb3DQEBCwUAMBgxFjAUBgNV
        BAMMDVR1aXN0IFRlc3QgQ0EwHhcNMjYwNzMwMTAyNzQzWhcNMzYwNzI3MTAyNzQz
        WjAYMRYwFAYDVQQDDA1UdWlzdCBUZXN0IENBMIIBIjANBgkqhkiG9w0BAQEFAAOC
        AQ8AMIIBCgKCAQEAqFVEuF4ifFLLwqHbmAq8n85/T48H9EZ+JgeNG/hqPohrEdYV
        xyqVUE3P486kMWiSBvj6DsiE52SYjpQ90UmvmZltgepdy5nas3O+l0PbP4t8RTnT
        UY8jKBd8XmW3/CXnf4UxRMN54SuY8ehsrxHFLjeW3IErDqwhFIT2okPKNRCZTY2t
        aUF5brOCenAA4fkrltFgTY6klIggRr4UtUgQXRqLAgNWH6wxiaqNpP+ObtZjNp5e
        YlgQxcJVkDso3fV+huvdjmh+mIrCmHRtHc6ctNqnH7E4NY6f5e0gURusJV+UX6xS
        T7UlKn0sGL9xUtKNJXnCH/UOOd5nzuENnSFbdwIDAQABoyMwITAPBgNVHRMBAf8E
        BTADAQH/MA4GA1UdDwEB/wQEAwIBBjANBgkqhkiG9w0BAQsFAAOCAQEAfmPzhf94
        F+CnPseiC6giYtrefx23r9G1P1e1wCSph5atFmdLW6Q2sDeab7LPSQUqnEx1/Q7I
        mYwgPNZExQoxBYla9zvqyC/TWYSR2768oLSwSAqGKa7iN+QiO+fFZJeelXW1Fz2z
        QQEd/RMZPotQMWTtoJ36gSwFrk8SraRT4l8E+iWhOTH+nNmPJWmcq3MPgL0j3aaS
        xuSsMl2S/1JBAVkwnsQt2Ldwxs8si7ACeeneESn1L22jtRiQJAvadurOOvmXYItY
        JJDM29xzYSuzuf7j46+zSYushfZ0faO9E9lp7PrYcUHNI4PPs1a3I/v5rtl1YtA8
        NQOawDBP+hdGwA==
        -----END CERTIFICATE-----
        """

        private static let leafPEM = """
        -----BEGIN CERTIFICATE-----
        MIIC+jCCAeKgAwIBAgIJAIUXHr1OMIzGMA0GCSqGSIb3DQEBCwUAMBgxFjAUBgNV
        BAMMDVR1aXN0IFRlc3QgQ0EwHhcNMjYwNzMwMTAyNzQzWhcNMjgxMTAxMTAyNzQz
        WjAUMRIwEAYDVQQDDAlsb2NhbGhvc3QwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAw
        ggEKAoIBAQCnuLlKIfwB1+UO5uF5TcH5Xte3bQKh3SE09tYOZwY6DBnRjlgsItdx
        OptnVUyLGzOQuld1TTdSTwlKnvehsflI5FnfRgIHnZTmf/K0N6nb69+JtGoQUhLs
        5PNjb/f8WnhFcV5XXkfaq6ufbEws1CCYiOEgKYVABKzGGnz35KZ5ed0oqmJLhHGX
        Bx143LiaqInNcYpxTL2VSCwVwDag595DCJLG3iMDznjiANLdHQGsXSabepYXKrP/
        qQ5e/F9aTdE1sZMeejCTyDzZwnCvTWLmMDbFYf74d5nuekDEzKsVr4/WCApKqr7t
        XoAln/ClUv7pGQQ0JoaFRj6vJ4oQ6T9TAgMBAAGjSzBJMAwGA1UdEwEB/wQCMAAw
        DgYDVR0PAQH/BAQDAgWgMBMGA1UdJQQMMAoGCCsGAQUFBwMBMBQGA1UdEQQNMAuC
        CWxvY2FsaG9zdDANBgkqhkiG9w0BAQsFAAOCAQEAp/g2avaiOwLIoqeDmIy8cwzy
        zXS66lX83cQeu+85cRH9vkyzYI+nCcY3ABSjf0rlAXST2LpUClQojfWZNaWaSP3Q
        scZlT+XJvAEP78AW4E7feUQOEGyRqaX2Qk0/xZf+P636rvubvq3r88JCnAN3h4jM
        PvPHjSYUPlCFkHi48Tkrlc9/OKrMdOLBMEgykKsaTx74fATC29IIgN3jnCySKNkE
        vr7vKkTQPNOMBkoDVqSHS/ilOzUm9+iKzDuYfUfjqy60kZWpioEt7dn9W8ittM6i
        wwJp2Lu3iXN62t6OCSv/QczDa/Q6ShpV8IQkikmAtEtecbzAmZz6m9utqQsugA==
        -----END CERTIFICATE-----
        """

        @Test
        func parses_single_PEM_certificate() {
            let certificates = CACertificateLoader.parse(from: Data(CACertificateLoaderTests.caPEM.utf8))
            #expect(certificates.count == 1)
        }

        @Test
        func parses_multiple_concatenated_PEM_certificates() {
            let bundle = CACertificateLoaderTests.caPEM + "\n" + CACertificateLoaderTests.leafPEM
            let certificates = CACertificateLoader.parse(from: Data(bundle.utf8))
            #expect(certificates.count == 2)
        }

        @Test
        func parses_DER_certificate_when_not_PEM() throws {
            // Strip the PEM armor to obtain the raw DER bytes, then confirm the loader
            // recognizes the DER blob as a single certificate.
            let body = CACertificateLoaderTests.caPEM
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.contains("----") }
                .joined()
            let derData = try #require(Data(base64Encoded: body))

            let certificates = CACertificateLoader.parse(from: derData)
            #expect(certificates.count == 1)
        }

        @Test
        func returns_empty_for_non_certificate_data() {
            let certificates = CACertificateLoader.parse(from: Data("not a certificate".utf8))
            #expect(certificates.isEmpty)
        }

        @Test
        func load_returns_nil_for_missing_file() {
            let certificates = CACertificateLoader.load(from: "/does/not/exist/ca.pem")
            #expect(certificates == nil)
        }

        @Test
        func validator_trusts_leaf_only_when_ca_is_added_as_anchor() throws {
            let leaf = try #require(CACertificateLoader.parse(from: Data(CACertificateLoaderTests.leafPEM.utf8)).first)
            let ca = try #require(CACertificateLoader.parse(from: Data(CACertificateLoaderTests.caPEM.utf8)).first)

            // Without the CA anchor the self-signed leaf is untrusted.
            let untrusted = try trust(for: leaf, hostname: "localhost")
            #expect(!TLSValidator.evaluate(untrusted, addingAdditionalAnchors: []))

            // With the CA added on top of the system root store the leaf validates.
            let trusted = try trust(for: leaf, hostname: "localhost")
            #expect(TLSValidator.evaluate(trusted, addingAdditionalAnchors: [ca]))

            // Hostname mismatch still fails even with the CA trusted: evaluation is not bypassed.
            let mismatched = try trust(for: leaf, hostname: "evil.com")
            #expect(!TLSValidator.evaluate(mismatched, addingAdditionalAnchors: [ca]))
        }

        private func trust(for certificate: SecCertificate, hostname: String) throws -> SecTrust {
            let policy = SecPolicyCreateSSL(true, hostname as CFString)
            var trust: SecTrust?
            let status = SecTrustCreateWithCertificates(certificate, policy, &trust)
            try #require(status == errSecSuccess)
            return try #require(trust)
        }
    }
#endif
