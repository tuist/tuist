import AuthenticationServices
import Foundation
import TuistAuthentication
import TuistErrorHandling

final class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    let authenticationService: AuthenticationService
    let errorHandling: ErrorHandling

    init(
        authenticationService: AuthenticationService,
        errorHandling: ErrorHandling
    ) {
        self.authenticationService = authenticationService
        self.errorHandling = errorHandling
    }

    func authorizationController(
        controller _: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        let authenticationService = authenticationService
        errorHandling.fireAndHandleError {
            try await authenticationService.signInWithApple(authorization: authorization)
        }
    }

    func authorizationController(controller _: ASAuthorizationController, didCompleteWithError error: Error) {
        errorHandling.handle(error: error)
    }

    func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
        return ASPresentationAnchor()
    }
}
