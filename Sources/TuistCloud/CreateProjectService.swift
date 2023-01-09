import Foundation
import Apollo
import TuistCloudSchema
import TuistSupport

public protocol CreateProjectServicing {
    func createProject(
        name: String,
        organizationName: String,
        serverURL: URL
    ) async throws
}

struct NetworkInterceptorProvider: InterceptorProvider {
    
    // These properties will remain the same throughout the life of the `InterceptorProvider`, even though they
    // will be handed to different interceptors.
    private let store: ApolloStore
    private let client: URLSessionClient
    private let serverURL: URL
    
    init(store: ApolloStore, client: URLSessionClient, serverURL: URL) {
        self.store = store
        self.client = client
        self.serverURL = serverURL
    }
    
    func interceptors<Operation: GraphQLOperation>(for operation: Operation) -> [ApolloInterceptor] {
        return [
            MaxRetryInterceptor(),
            CacheReadInterceptor(store: store),
            AuthenticationTokenManagementInterceptor(serverURL: serverURL),
            NetworkFetchInterceptor(client: client),
            ResponseCodeInterceptor(),
            JSONResponseParsingInterceptor(),
            AutomaticPersistedQueryInterceptor(),
            CacheReadInterceptor(store: self.store),
        ]
    }
}

private final class AuthenticationTokenManagementInterceptor: ApolloInterceptor {
    enum AuthenticationError: Error {
      case tokenNotFound
    }
    
    private let serverURL: URL
    init(serverURL: URL) {
        self.serverURL = serverURL
    }
    
    public func interceptAsync<Operation>(
        chain: RequestChain,
        request: HTTPRequest<Operation>,
        response: HTTPResponse<Operation>?,
        completion: @escaping (Result<GraphQLResult<Operation.Data>, Error>) -> Void
    ) where Operation : GraphQLOperation {
        let environment = ProcessInfo.processInfo.environment
        let tokenFromEnvironment = environment[Constants.EnvironmentVariables.cloudToken]
        let token: String?
        if CIChecker().isCI() {
            token = tokenFromEnvironment
        } else {
            token = try? tokenFromEnvironment ?? CredentialsStore().read(serverURL: serverURL)?.token
        }
        if let token = token {
            request.addHeader(name: "Authorization", value: "Bearer \(token)")
            chain.proceedAsync(request: request, response: response, completion: completion)
        } else {
            do {
                try CloudSessionController().authenticate(serverURL: serverURL)
                chain.retry(request: request, completion: completion)
            } catch let error {
                chain.handleErrorAsync(
                    error,
                    request: request,
                    response: response,
                    completion: completion
                )
            }
        }
    }
}

public final class CreateProjectService: CreateProjectServicing {
    public init() {}
    
    public func createProject(
        name: String,
        organizationName: String,
        serverURL: URL
    ) async throws {
        let client: ApolloClient = {
            // The cache is necessary to set up the store, which we're going
            // to hand to the provider
            let cache = InMemoryNormalizedCache()
            let store = ApolloStore(cache: cache)

            let client = URLSessionClient()
            let provider = NetworkInterceptorProvider(store: store, client: client, serverURL: serverURL)
            let url = serverURL.appendingPathComponent("graphql")

            let requestChainTransport = RequestChainNetworkTransport(
                interceptorProvider: provider,
                endpointURL: url
            )

            // Remember to give the store you already created to the client so it
            // doesn't create one on its own
            return ApolloClient(networkTransport: requestChainTransport, store: store)
        }()
        
        let response = await withCheckedContinuation { continuation in
            client.perform(
                mutation: CreateProjectMutation(
                    input: CreateProjectInput(
                        name: name,
                        accountName: GraphQLNullable(stringLiteral: organizationName)
                    )
                )
            ) { response in
                continuation.resume(returning: response)
            }
        }
        _ = try response.get()
    }
}
