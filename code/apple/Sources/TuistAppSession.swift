#if os(macOS)
    import Foundation
    import Security

    /// The Tuist app's session: `ServerCredentialsStore`'s Keychain backend stores
    /// internet passwords for the server's host, with accounts named
    /// `<canonical server URL>_<field>`. Tuist Code reads them and updates the token
    /// items in place; it never creates or deletes them, so the Tuist app keeps its
    /// access. The Rust core holds the shared refresh lock around every update.
    enum TuistAppSession {
        static func list() throws -> [String] {
            var query = base()
            query[kSecMatchLimit as String] = kSecMatchLimitAll
            query[kSecReturnAttributes as String] = true
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { return [] }
            guard status == errSecSuccess, let items = result as? [[String: Any]] else { throw failure }
            let keys = items.compactMap { item -> String? in
                guard let account = item[kSecAttrAccount as String] as? String,
                      account.hasSuffix("_refresh_token")
                else { return nil }
                let key = String(account.dropLast("_refresh_token".count))
                return URL(string: key)?.host == item[kSecAttrServer as String] as? String ? key : nil
            }
            return Array(Set(keys)).sorted()
        }

        static func read(_ key: String) throws -> [String: Any]? {
            guard let access = try value(key, "access_token") else { return nil }
            return [
                "access_token": access,
                "refresh_token": try value(key, "refresh_token") ?? NSNull(),
                "oauth_client_id": try value(key, "oauth_client_id") ?? NSNull(),
                "rejected": try value(key, "rejected") == "true",
            ]
        }

        /// Refresh first, as `ServerCredentialsStore.store` does, so a partial
        /// write leaves a usable refresh token.
        static func write(_ key: String, access: String, refresh: String) throws {
            for (field, text) in [("refresh_token", refresh), ("access_token", access)] {
                let status = SecItemUpdate(
                    try item(key, field) as CFDictionary,
                    [kSecValueData as String: Data(text.utf8)] as CFDictionary
                )
                guard status == errSecSuccess else { throw failure }
            }
        }

        private static func value(_ key: String, _ field: String) throws -> String? {
            var query = try item(key, field)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess, let data = result as? Data else { throw failure }
            return String(data: data, encoding: .utf8)
        }

        /// KeychainAccess's `Keychain(server:protocolType: .https, authenticationType: .default)` query.
        private static func item(_ key: String, _ field: String) throws -> [String: Any] {
            guard let url = URL(string: key), let host = url.host else { throw failure }
            var query = base()
            query[kSecAttrServer as String] = host
            query[kSecAttrAccount as String] = "\(key)_\(field)"
            if let port = url.port { query[kSecAttrPort as String] = port }
            return query
        }

        private static func base() -> [String: Any] {
            [
                kSecClass as String: kSecClassInternetPassword,
                kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
                kSecAttrAuthenticationType as String: kSecAttrAuthenticationTypeDefault,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            ]
        }

        private static var failure: Error {
            NSError(domain: "dev.tuist.code", code: 1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "The Tuist app's session could not be read or updated."),
            ])
        }
    }
#endif
