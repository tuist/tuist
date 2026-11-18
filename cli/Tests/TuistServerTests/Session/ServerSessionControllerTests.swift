import Foundation
import HTTPTypes
import Mockable
import OpenAPIRuntime
import TuistOpener
import TuistSupport
import TuistUniqueIDGenerator
import XCTest

@testable import TuistServer
@testable import TuistTesting

final class ServerSessionControllerTests: TuistUnitTestCase {
    private var credentialsStore: MockServerCredentialsStoring!
    private var opener: MockOpening!
    private var serverURL: URL!
    private var getAuthTokenService: MockGetAuthTokenServicing!
    private var deviceCodeTransport: DeviceCodeTransport!
    private var uniqueIDGenerator: MockUniqueIDGenerating!
    private var serverAuthenticationController: MockServerAuthenticationControlling!
    private var subject: ServerSessionController!

    override func setUp() {
        super.setUp()
        credentialsStore = .init()
        serverURL = URL.test()
        getAuthTokenService = MockGetAuthTokenServicing()
        deviceCodeTransport = DeviceCodeTransport()
        uniqueIDGenerator = MockUniqueIDGenerating()
        serverAuthenticationController = MockServerAuthenticationControlling()
        opener = MockOpening()
        subject = ServerSessionController(
            opener: opener,
            getAuthTokenService: getAuthTokenService,
            createDeviceCodeService: CreateDeviceCodeService(makeClient: { [deviceCodeTransport] url in
                Client(serverURL: url, transport: deviceCodeTransport!)
            }),
            uniqueIDGenerator: uniqueIDGenerator,
            serverAuthenticationController: serverAuthenticationController
        )

        given(opener)
            .open(url: .any)
            .willReturn()
    }

    override func tearDown() {
        credentialsStore = nil
        opener = nil
        serverURL = nil
        deviceCodeTransport = nil
        uniqueIDGenerator = nil
        serverAuthenticationController = nil
        subject = nil
        super.tearDown()
    }

    func test_authenticate_showsUserCodeOpensVerificationURLAndPollsWithDeviceCode() async throws {
        try await withMockedDependencies {
            // Given
            // Fields the server may add later, like `verification_uri_complete`, must not break decoding.
            deviceCodeTransport.response = (.ok, """
            {
              "device_code": "device-secret",
              "user_code": "WDJB-MJHT",
              "verification_uri": "https://tuist.example/auth/device",
              "verification_uri_complete": "https://tuist.example/auth/device?code=WDJB-MJHT",
              "expires_in": 300,
              "interval": 1
            }
            """)
            given(getAuthTokenService)
                .getAuthToken(serverURL: .any, deviceCode: .any)
                .willReturn(ServerAuthenticationTokens(accessToken: "access-token", refreshToken: "refresh-token"))
            let serverCredentialsStore = try XCTUnwrap(ServerCredentialsStore.mocked)
            given(serverCredentialsStore).store(credentials: .any, serverURL: .any).willReturn()
            let verificationURL = try XCTUnwrap(URL(string: "https://tuist.example/auth/device"))

            // When
            var events: [String] = []
            try await subject.authenticate(
                serverURL: serverURL,
                deviceCodeType: .cli,
                onUserCode: { events.append("userCode:\($0)") },
                onOpeningBrowser: { events.append("openingBrowser:\($0.absoluteString)") },
                onAuthWaitBegin: { events.append("waitBegin") }
            )

            // Then
            XCTAssertEqual(events, [
                "userCode:WDJB-MJHT",
                "openingBrowser:https://tuist.example/auth/device",
                "waitBegin",
            ])
            XCTAssertEqual(deviceCodeTransport.requests, ["POST /api/auth/device_codes"])
            verify(opener).open(url: .value(verificationURL)).called(1)
            verify(getAuthTokenService)
                .getAuthToken(serverURL: .value(serverURL), deviceCode: .value("device-secret"))
                .called(1)
            verify(uniqueIDGenerator).uniqueID().called(0)
            verify(serverCredentialsStore)
                .store(
                    credentials: .value(ServerCredentials(accessToken: "access-token", refreshToken: "refresh-token")),
                    serverURL: .value(serverURL)
                )
                .called(1)
        }
    }

    func test_authenticate_fallsBackToLinkFlow_when_serverRespondsNotFound() async throws {
        try await assertFallsBackToLinkFlow(status: .notFound)
    }

    func test_authenticate_fallsBackToLinkFlow_when_serverRespondsMethodNotAllowed() async throws {
        try await assertFallsBackToLinkFlow(status: .methodNotAllowed)
    }

    private func assertFallsBackToLinkFlow(status: HTTPResponse.Status) async throws {
        try await withMockedDependencies {
            // Given
            deviceCodeTransport.response = (status, #"{"message":"Not found"}"#)
            given(getAuthTokenService)
                .getAuthToken(serverURL: .any, deviceCode: .any)
                .willReturn(ServerAuthenticationTokens(accessToken: "access-token", refreshToken: "refresh-token"))
            given(uniqueIDGenerator).uniqueID().willReturn("id")
            let serverCredentialsStore = try XCTUnwrap(ServerCredentialsStore.mocked)
            given(serverCredentialsStore).store(credentials: .any, serverURL: .any).willReturn()

            // When
            var userCode: String?
            var authURLOpened: URL?
            try await subject.authenticate(
                serverURL: serverURL,
                deviceCodeType: .cli,
                onUserCode: { userCode = $0 },
                onOpeningBrowser: { authURLOpened = $0 },
                onAuthWaitBegin: {}
            )

            // Then
            XCTAssertNil(userCode)
            XCTAssertEqual(authURLOpened, authURL())
            XCTAssertEqual(deviceCodeTransport.requests, ["POST /api/auth/device_codes"])
            verify(opener).open(url: .value(authURL())).called(1)
            verify(getAuthTokenService)
                .getAuthToken(serverURL: .value(serverURL), deviceCode: .value("id"))
                .called(1)
            verify(serverCredentialsStore).store(credentials: .any, serverURL: .value(serverURL)).called(1)
        }
    }

    func test_authenticate_throwsWithoutFallingBack_when_creatingTheDeviceCodeFailsWithAServerError() async throws {
        // Given
        deviceCodeTransport.response = (.internalServerError, #"{"message":"Internal server error"}"#)

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.authenticate(
                serverURL: serverURL,
                deviceCodeType: .cli,
                onUserCode: { _ in },
                onOpeningBrowser: { _ in },
                onAuthWaitBegin: {}
            ),
            CreateDeviceCodeServiceError.unknownError(500)
        )
        verify(opener).open(url: .any).called(0)
        verify(getAuthTokenService).getAuthToken(serverURL: .any, deviceCode: .any).called(0)
    }

    func test_authenticate_stopsPolling_when_theDeviceCodeExpires() async throws {
        // Given
        deviceCodeTransport.response = (.ok, """
        {"device_code": "device-secret", "user_code": "WDJB-MJHT",
         "verification_uri": "https://tuist.example/auth/device", "expires_in": 0, "interval": 1}
        """)
        given(getAuthTokenService)
            .getAuthToken(serverURL: .any, deviceCode: .any)
            .willReturn(nil)

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.authenticate(
                serverURL: serverURL,
                deviceCodeType: .cli,
                onUserCode: { _ in },
                onOpeningBrowser: { _ in },
                onAuthWaitBegin: {}
            ),
            ServerSessionControllerError.deviceCodeExpired
        )
        verify(getAuthTokenService)
            .getAuthToken(serverURL: .value(serverURL), deviceCode: .value("device-secret"))
            .called(1)
    }

    func test_authenticate_usesLinkFlow_when_deviceCodeTypeIsApp() async throws {
        try await withMockedDependencies {
            // Given
            given(getAuthTokenService)
                .getAuthToken(serverURL: .any, deviceCode: .any)
                .willReturn(ServerAuthenticationTokens(accessToken: "access-token", refreshToken: "refresh-token"))
            given(uniqueIDGenerator).uniqueID().willReturn("id")
            let serverCredentialsStore = try XCTUnwrap(ServerCredentialsStore.mocked)
            given(serverCredentialsStore).store(credentials: .any, serverURL: .any).willReturn()

            // When
            var authURLOpened: URL?
            try await subject.authenticate(
                serverURL: serverURL,
                deviceCodeType: .app,
                onUserCode: { _ in },
                onOpeningBrowser: { authURLOpened = $0 },
                onAuthWaitBegin: {}
            )

            // Then
            XCTAssertEqual(authURLOpened, authURL(type: "app"))
            XCTAssertEqual(deviceCodeTransport.requests, [])
        }
    }

    func test_whoami_when_logged_in() async throws {
        // Given
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .value(serverURL))
            .willReturn(
                .user(
                    accessToken: .test(
                        email: "tuist@tuist.dev",
                        preferredUsername: "tuist"
                    ),
                    refreshToken: .test(
                        email: "tuist@tuist.dev",
                        preferredUsername: "tuist"
                    )
                )
            )

        // When
        let got = try await subject.whoami(serverURL: serverURL)

        // Then
        XCTAssertEqual(got, "tuist")
    }

    func test_whoami_when_logged_out() async throws {
        // Given
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .value(serverURL))
            .willReturn(
                nil
            )

        // When
        let got = try await subject.whoami(serverURL: serverURL)

        // Then
        XCTAssertEqual(got, nil)
    }

    func test_get_authenticated_handle_when_logged_in() async throws {
        // Given
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .value(serverURL))
            .willReturn(
                .user(
                    accessToken: .test(
                        email: "tuist@tuist.dev",
                        preferredUsername: "tuist"
                    ),
                    refreshToken: .test(
                        email: "tuist@tuist.dev",
                        preferredUsername: "tuist"
                    )
                )
            )

        // When
        let got = try await subject.whoami(serverURL: serverURL)

        // Then
        XCTAssertEqual(got, "tuist")
    }

    func test_get_authenticated_handle_when_signed_in_with_an_account_token() async throws {
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .value(serverURL))
            .willReturn(.account(.test(preferredUsername: "tuist-org")))

        let got = try await subject.authenticatedHandle(serverURL: serverURL)

        XCTAssertEqual(got, "tuist-org")
    }

    func test_get_authenticated_handle_when_logged_out() async throws {
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .value(serverURL))
            .willReturn(
                nil
            )

        // Then
        await XCTAssertThrowsSpecific(
            try await subject.authenticatedHandle(serverURL: serverURL),
            ServerSessionControllerError.unauthenticated
        )
    }

    func test_logout_deletesCredentials() async throws {
        try await withMockedDependencies {
            // Given
            let serverCredentialsStore = try XCTUnwrap(ServerCredentialsStore.mocked)
            given(serverCredentialsStore)
                .delete(serverURL: .any)
                .willReturn()
            let credentials = ServerCredentials(
                accessToken: "access-token",
                refreshToken: "refresh-token"
            )
            given(credentialsStore)
                .store(credentials: .value(credentials), serverURL: .value(serverURL))
                .willReturn()
            try await credentialsStore.store(credentials: credentials, serverURL: serverURL)

            given(credentialsStore)
                .delete(serverURL: .value(serverURL))
                .willReturn()

            // When
            try await subject.logout(serverURL: serverURL)
        }
    }

    fileprivate func authURL(type: String = "cli") -> URL {
        var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)!
        components.path = "/auth/device_codes/id"
        components.queryItems = [
            URLQueryItem(name: "type", value: type),
        ]
        return components.url!
    }
}

private final class DeviceCodeTransport: ClientTransport, @unchecked Sendable {
    var response: (HTTPResponse.Status, String) = (.notFound, "")
    private(set) var requests: [String] = []

    func send(
        _ request: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID _: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        requests.append("\(request.method.rawValue) \(request.path ?? "")")
        var httpResponse = HTTPResponse(status: response.0)
        httpResponse.headerFields[.contentType] = "application/json"
        return (httpResponse, HTTPBody(response.1))
    }
}
