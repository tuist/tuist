import Foundation

extension URLRequest {
    public var descriptionForError: String {
        guard let url = url, let httpMethod = httpMethod else { return "url request without any http method nor url set" }
        return "an url request that sends a \(httpMethod) request to url '\(url)'"
    }
}
