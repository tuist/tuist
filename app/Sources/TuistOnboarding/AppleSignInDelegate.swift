import Foundation
import AuthenticationServices
import TuistAuthentication
import TuistErrorHandling

final class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    let authenticationService: AuthenticationService
    let errorHandling: ErrorHandling
    
    init(
        authenticationService: AuthenticationService,
        errorHandling: ErrorHandling
    ) {
        self.authenticationService = authenticationService
        self.errorHandling = errorHandling
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        let authenticationService = authenticationService
        errorHandling.fireAndHandleError {
            try await authenticationService.signInWithApple(authorization: authorization)
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        errorHandling.handle(error: error)
    }
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return ASPresentationAnchor()
    }
}
