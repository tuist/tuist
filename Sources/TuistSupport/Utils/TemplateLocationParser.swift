import Foundation

public protocol TemplateLocationParsing {
    /// Extract branch's name if it exist from given template URL. If not return nil
    /// - Parameters:
    ///   - templateURL: given template URL
    func parseRepositoryBranch(from templateURL: String) -> String?
    /// Extract repo URL from given template URL.
    /// - Parameters:
    ///   - templateURL: given template URL
    func parseRepositoryURL(from templateURL: String) -> String
}

/// An implementation of `TemplateLocationParsing`
public final class TemplateLocationParser: TemplateLocationParsing {
    private let system: Systeming

    public init(
        system: Systeming = System.shared
    ) {
        self.system = system
    }

    public func parseRepositoryBranch(from templateURL: String) -> String? {
        let splittedURL = templateURL
            .split(separator: "@")
        guard let branch = splittedURL.last,
              splittedURL.count >= 2
        else {
            return nil
        }
        if let url = splittedURL.first, splittedURL.count == 2,
           !String(url).matches(pattern: String.httpRegularExpression)
        {
            return nil
        } else {
            return String(branch)
        }
    }

    public func parseRepositoryURL(from templateURL: String) -> String {
        let splittedURL = templateURL
            .split(separator: "@")

        if splittedURL.count < 2, !splittedURL.isEmpty {
            return templateURL
        } else if splittedURL.count == 2 {
            if let remoteURl = splittedURL.first,
               String(remoteURl).matches(pattern: String.httpRegularExpression)
            {
                return String(remoteURl)
            } else {
                return String(
                    splittedURL
                        .reduce("") { $0 + "@" + $1 }
                        .dropFirst()
                )
            }
        } else {
            return String(
                splittedURL
                    .dropLast()
                    .reduce("") { $0 + "@" + $1 }
                    .dropFirst()
            )
        }
    }
}
