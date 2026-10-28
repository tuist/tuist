import Foundation
import Mockable
import Synchronization
import Testing
import TuistOpener
import TuistSupport
import TuistUniqueIDGenerator
@testable import TuistServer

struct ServerSessionControllerProgramStatusTests {
    private enum TestError: Error {
        case failed
    }

    @Test(arguments: [false, true])
    func authenticate_reportsBlockedWhileWaitingForBrowserAndRestoresWorking(shouldFail: Bool) async throws {
        let reports = Mutex<[String]>([])
        let statusReporter = ProgramStatusReporter(isEnabled: true) { report in
            reports.withLock { $0.append(report) }
        }
        let opener = MockOpening()
        let getAuthTokenService = MockGetAuthTokenServicing()
        let uniqueIDGenerator = MockUniqueIDGenerating()
        let credentialsStore = MockServerCredentialsStoring()
        let subject = ServerSessionController(
            opener: opener,
            getAuthTokenService: getAuthTokenService,
            uniqueIDGenerator: uniqueIDGenerator,
            serverAuthenticationController: MockServerAuthenticationControlling()
        )
        let serverURL = try #require(URL(string: "https://tuist.dev"))
        given(opener).open(url: .any).willReturn()
        given(uniqueIDGenerator).uniqueID().willReturn("device-code")
        given(credentialsStore).store(credentials: .any, serverURL: .any).willReturn()
        given(getAuthTokenService).getAuthToken(serverURL: .any, deviceCode: .any).willProduce { _, _ in
            #expect(reports.withLock { $0.last?.contains("state=blocked:app=tuist:kind=auth:msg=") } == true)
            if shouldFail { throw TestError.failed }
            return ServerAuthenticationTokens(accessToken: "access-token", refreshToken: "refresh-token")
        }

        try await ProgramStatusReporter.$current.withValue(statusReporter) {
            try await ServerCredentialsStore.$current.withValue(credentialsStore) {
                let authenticate = {
                    try await subject.authenticate(
                        serverURL: serverURL,
                        deviceCodeType: .cli,
                        onOpeningBrowser: { _ in },
                        onAuthWaitBegin: {}
                    )
                }
                if shouldFail {
                    await #expect(throws: TestError.failed) { try await authenticate() }
                } else {
                    try await authenticate()
                }
            }
        }

        let output = reports.withLock { $0 }
        #expect(output.count == 2)
        #expect(output.last?.contains("state=working:app=tuist") == true)
        verify(credentialsStore).store(credentials: .any, serverURL: .any).called(shouldFail ? 0 : 1)
    }
}
