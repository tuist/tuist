import Foundation

extension URLRequest {
    public var descriptionForError: String {
        guard let url, let httpMethod else { return "url request without any http method nor url set" }
        return "an url request that sends a \(httpMethod) request to url '\(url)'"
    }
}
