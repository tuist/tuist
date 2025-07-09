import AuthenticationServices
import Foundation
import TuistAuthentication
import TuistErrorHandling

final class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    let authenticationService: AuthenticationService
    let errorHandler: ErrorHandling

    init(
        authenticationService: AuthenticationService,
        errorHandler: ErrorHandling
    ) {
        self.authenticationService = authenticationService
        self.errorHandler = errorHandler
    }

    func authorizationController(
        controller _: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        let authenticationService = authenticationService
        errorHandler.fireAndHandleError {
            try await authenticationService.signInWithApple(authorization: authorization)
        }
    }

    func authorizationController(controller _: ASAuthorizationController, didCompleteWithError error: Error) {
        errorHandler.handle(error: error)
    }

    func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
        return ASPresentationAnchor()
    }
}
