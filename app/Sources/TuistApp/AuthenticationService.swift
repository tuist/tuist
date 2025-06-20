import Foundation
import SwiftUI
import TuistServer

@MainActor
public class AuthenticationService: ObservableObject {
    @Published public var isAuthenticated: Bool = false
    
    private let serverCredentialsStore: ServerCredentialsStoring
    private let serverURL: URL
    
    public init(
        serverCredentialsStore: ServerCredentialsStoring = ServerCredentialsStore(),
        serverURL: URL = URL(string: "http://localhost:8080")!
    ) {
        self.serverCredentialsStore = serverCredentialsStore
        self.serverURL = serverURL
        
        Task {
            await checkAuthentication()
        }
    }
    
    public func checkAuthentication() async {
        do {
            let credentials = try await serverCredentialsStore.read(serverURL: serverURL)
            isAuthenticated = credentials?.refreshToken != nil
        } catch {
            isAuthenticated = false
        }
    }
    
    public func signOut() async {
        do {
            try await serverCredentialsStore.delete(serverURL: serverURL)
            isAuthenticated = false
        } catch {
            // Handle error if needed
        }
    }
}