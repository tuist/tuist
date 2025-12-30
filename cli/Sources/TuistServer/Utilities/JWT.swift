import Foundation

enum JWTError: Equatable, LocalizedError {
    case invalidJWT(String)

    var errorDescription: String? {
        switch self {
        case let .invalidJWT(token):
            return
                "The access token \(token) is invalid. Try to reauthenticate by running 'tuist auth login'."
        }
    }
}

public struct JWT: Equatable {
    private struct JWTPayload: Codable {
        let exp: Int
        let email: String?
        // swiftlint:disable:next identifier_name
        let preferred_username: String?
        let type: String?
    }

    public let token: String
    public let expiryDate: Date
    public let email: String?
    public let preferredUsername: String?
    public let type: String?

    static func make(
        expiryDate: Date,
        typ: String = "JWT",
        email: String? = nil,
        preferredUsername: String? = nil,
        type: String? = nil
    ) throws -> JWT {
        let header = [
            "alg": "none",
            "typ": typ,
        ]

        // Create payload
        let payload = JWTPayload(
            exp: Int(expiryDate.timeIntervalSince1970),
            email: email,
            preferred_username: preferredUsername,
            type: type
        )

        // Encode header and payload
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = .sortedKeys

        let headerData = try jsonEncoder.encode(header)
        let headerBase64URL = Self.base64URLEncode(headerData)

        let payloadData = try jsonEncoder.encode(payload)
        let payloadBase64URL = Self.base64URLEncode(payloadData)

        return JWT(
            token: "\(headerBase64URL).\(payloadBase64URL).",
            expiryDate: expiryDate,
            email: email,
            preferredUsername: preferredUsername,
            type: type
        )
    }

    private static func base64URLEncode(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func parse(_ jwt: String) throws -> JWT {
        let components = jwt.components(separatedBy: ".")
        guard components.count == 3
        else {
            throw JWTError.invalidJWT(jwt)
        }

        let jwtEncodedPayload = components[1]

        // Add padding if needed
        let remainder = jwtEncodedPayload.count % 4
        let paddedJWTEncodedPayload: String
        if remainder > 0 {
            paddedJWTEncodedPayload = jwtEncodedPayload.padding(
                toLength: jwtEncodedPayload.count + 4 - remainder,
                withPad: "=",
                startingAt: 0
            )
        } else {
            paddedJWTEncodedPayload = jwtEncodedPayload
        }

        // Convert Base64URL back to Base64
        let base64String = paddedJWTEncodedPayload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        guard let data = Data(base64Encoded: base64String)
        else {
            throw JWTError.invalidJWT(jwtEncodedPayload)
        }

        let jsonDecoder = JSONDecoder()
        let payload = try jsonDecoder.decode(JWTPayload.self, from: data)

        return JWT(
            token: jwt,
            expiryDate: Date(timeIntervalSince1970: TimeInterval(payload.exp)),
            email: payload.email,
            preferredUsername: payload.preferred_username,
            type: payload.type
        )
    }
}

#if DEBUG
    extension JWT {
        public static func test(
            token: String = "token",
            expiryDate: Date = Date(),
            email: String? = nil,
            preferredUsername: String? = nil,
            type: String? = nil
        ) -> JWT {
            .init(
                token: token,
                expiryDate: expiryDate,
                email: email,
                preferredUsername: preferredUsername,
                type: type
            )
        }
    }
#endif
