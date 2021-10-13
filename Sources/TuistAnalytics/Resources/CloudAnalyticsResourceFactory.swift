import Foundation
import TuistCore
import TuistGraph
import TuistSupport

typealias CloudStoreResource = HTTPResource<Void, CloudEmptyResponseError>

/// Entity responsible for providing analytics-related resources
protocol CloudAnalyticsResourceFactorying {
    func storeResource(commandEvent: CommandEvent) throws -> CloudStoreResource
}

class CloudAnalyticsResourceFactory: CloudAnalyticsResourceFactorying {
    private let cloudConfig: Cloud

    init(cloudConfig: Cloud) {
        self.cloudConfig = cloudConfig
    }

    func storeResource(commandEvent: CommandEvent) throws -> CloudStoreResource {
        let url = apiAnalyticsURL(cacheURL: cloudConfig.url, projectId: cloudConfig.projectId)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let encodedCommandEvent = try encoder.encode(commandEvent)
        request.httpBody = encodedCommandEvent
        
        return HTTPResource(
            request: { request },
            parse: { _, _ in () },
            parseError: { _, _ in CloudEmptyResponseError() }
        )
    }

    // MARK: Private

    private func apiAnalyticsURL(
        cacheURL: URL,
        projectId: String
    ) -> URL {
        var urlComponents = URLComponents(url: cacheURL, resolvingAgainstBaseURL: false)!
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "project_id", value: projectId),
        ]

        urlComponents.path = "/api/analytics"
        urlComponents.queryItems = queryItems
        return urlComponents.url!
    }
}
