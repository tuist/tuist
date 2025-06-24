import Foundation
import SwiftUI
import TuistServer
import Combine

@MainActor
public class AuthenticationService: ObservableObject {
    @Published public var isAuthenticated: Bool = false
    
    private let serverCredentialsStore: ServerCredentialsStore
    private let serverURL: URL
    private var cancellables = Set<AnyCancellable>()
    
    public init(
        serverCredentialsStore: ServerCredentialsStore = ServerCredentialsStore(),
        serverURL: URL = URL(string: "http://localhost:8080")!
    ) {
        self.serverCredentialsStore = serverCredentialsStore
        self.serverURL = serverURL
        
        setupCredentialsListener()
        
        Task {
            await checkAuthentication()
        }
    }
    
    private func setupCredentialsListener() {
        ServerCredentialsStore.credentialsChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] credentials in
                self?.isAuthenticated = credentials?.refreshToken != nil
            }
            .store(in: &cancellables)
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
        } catch {
            // Handle error if needed
        }
    }
}
