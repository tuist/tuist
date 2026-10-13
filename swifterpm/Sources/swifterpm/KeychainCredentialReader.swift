import Foundation

#if canImport(Security)
    /// Legacy login-keychain approval is controlled by a process-wide Security setting,
    /// not LAContext. Run the lookup in an isolated Swift interpreter so disabling UI
    /// cannot race with another Tuist subsystem or alter the caller's keychain policy.
    enum KeychainCredentialReader {
        private struct Reply: Decodable {
            let status: Int32
            let user: String?
            let password: String?
        }

        static func credential(for url: URL) async throws -> RegistryCredential? {
            guard let host = url.host?.lowercased(), !host.isEmpty else { return nil }
            let failure = "failed to perform a noninteractive keychain lookup for \(host)"
            let result = try await SystemProcess.run(
                "swift", [
                    "-suppress-warnings",
                    "-",
                    host,
                    url.scheme == "http" ? "http" : "https",
                    url.port.map(String.init) ?? "",
                ],
                input: source, failureMessage: failure, outputLimit: 64 * 1024
            )
            return try decodeReply(result.stdout, host: host)
        }

        static func decodeReply(_ data: Data, host: String) throws -> RegistryCredential? {
            let failure = "failed to perform a noninteractive keychain lookup for \(host)"
            let reply: Reply
            do {
                reply = try JSONDecoder().decode(Reply.self, from: data)
            } catch {
                // Decoder errors and subprocess output must never include a credential.
                throw ToolError.message(failure)
            }
            guard try KeychainAuthorization.lookupSucceeded(reply.status, host: host) else { return nil }
            guard let user = reply.user, let password = reply.password else { throw ToolError.message(failure) }
            return RegistryCredential(user: user, password: password)
        }

        static let source = """
        import Foundation
        import Security

        func reply(_ status: OSStatus, credential: [String: Any]? = nil) -> Never {
            var value: [String: Any] = ["status": status]
            if status == errSecSuccess,
               let user = credential?[kSecAttrAccount as String] as? String,
               let password = credential?[kSecValueData as String] as? Data {
                value["user"] = user
                value["password"] = String(decoding: password, as: UTF8.self)
            }
            guard let data = try? JSONSerialization.data(withJSONObject: value) else { exit(1) }
            FileHandle.standardOutput.write(data)
            exit(0)
        }

        let interactionStatus = SecKeychainSetUserInteractionAllowed(false)
        guard interactionStatus == errSecSuccess else { reply(interactionStatus) }
        let host = CommandLine.arguments[1]
        let securityProtocol = CommandLine.arguments[2] == "http" ? kSecAttrProtocolHTTP : kSecAttrProtocolHTTPS
        var query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrProtocol as String: securityProtocol,
            kSecAttrServer as String: host,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        if let port = Int(CommandLine.arguments[3]) { query[kSecAttrPort as String] = port }
        var items: CFTypeRef?
        let searchStatus = SecItemCopyMatching(query as CFDictionary, &items)
        guard searchStatus == errSecSuccess else { reply(searchStatus) }
        guard let matches = items as? [[String: Any]],
              let newest = matches.sorted(by: {
                  switch ($0[kSecAttrModificationDate as String] as? Date, $1[kSecAttrModificationDate as String] as? Date) {
                  case (nil, nil): return false
                  case (_, nil): return true
                  case (nil, _): return false
                  case (.some(let left), .some(let right)): return left < right
                  }
              }).last,
              let created = newest[kSecAttrCreationDate as String] as? Date
        else { reply(errSecDecode) }
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        query[kSecAttrCreationDate as String] = created
        if let modified = newest[kSecAttrModificationDate as String] as? Date {
            query[kSecAttrModificationDate as String] = modified
        }
        var item: CFTypeRef?
        let readStatus = SecItemCopyMatching(query as CFDictionary, &item)
        reply(readStatus, credential: item as? [String: Any])
        """
    }
#endif
