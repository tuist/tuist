import Apollo
import Foundation
import TuistSupport

extension ApolloClient {
    convenience init(cloudURL: URL) {
        let store = ApolloStore(cache: InMemoryNormalizedCache())

        let client = URLSessionClient()
        let provider = NetworkInterceptorProvider(store: store, client: client, serverURL: cloudURL)
        let url = cloudURL.appendingPathComponent("graphql")

        let requestChainTransport = RequestChainNetworkTransport(
            interceptorProvider: provider,
            endpointURL: url
        )

        self.init(networkTransport: requestChainTransport, store: store)
    }
}

private struct NetworkInterceptorProvider: InterceptorProvider {
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

    func interceptors<Operation: GraphQLOperation>(for _: Operation) -> [ApolloInterceptor] {
        [
            MaxRetryInterceptor(),
            CacheReadInterceptor(store: store),
            AuthenticationTokenManagementInterceptor(serverURL: serverURL),
            NetworkFetchInterceptor(client: client),
            ResponseCodeInterceptor(),
            JSONResponseParsingInterceptor(),
            AutomaticPersistedQueryInterceptor(),
            CacheReadInterceptor(store: store),
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
    ) where Operation: GraphQLOperation {
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
            } catch {
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
