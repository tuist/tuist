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
    }

    public let token: String
    public let expiryDate: Date
    public let email: String?
    public let preferredUsername: String?

    func encode() throws -> String {
        // Create header (typically static for most JWTs)
        let header = [
            "alg": "HS256", // or whatever algorithm you're using
            "typ": "JWT",
        ]

        // Create payload
        let payload = JWTPayload(
            exp: Int(expiryDate.timeIntervalSince1970),
            email: email,
            preferred_username: preferredUsername
            // Add any other fields your JWTPayload has
        )

        // Encode header
        let jsonEncoder = JSONEncoder()
        let headerData = try jsonEncoder.encode(header)
        let headerBase64 = headerData.base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")

        // Encode payload
        let payloadData = try jsonEncoder.encode(payload)
        let payloadBase64 = payloadData.base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")

        // For a complete JWT, you'd need to sign it with a secret key
        // This is a simplified version that creates an unsigned token
        let unsignedToken = "\(headerBase64).\(payloadBase64)"

        // In a real implementation, you'd create a signature here
        // let signature = createSignature(unsignedToken, secret: secretKey)
        // return "\(unsignedToken).\(signature)"

        // For now, returning unsigned token with empty signature
        return "\(unsignedToken)."
    }

    public static func parse(_ jwt: String) throws -> JWT {
        let components = jwt.components(separatedBy: ".")
        guard components.count == 3
        else {
            throw JWTError.invalidJWT(jwt)
        }
        let jwtEncodedPayload = components[1]
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
        guard let data = Data(base64Encoded: paddedJWTEncodedPayload)
        else {
            throw JWTError.invalidJWT(jwtEncodedPayload)
        }
        let jsonDecoder = JSONDecoder()
        let payload = try jsonDecoder.decode(JWTPayload.self, from: data)

        return JWT(
            token: jwt,
            expiryDate: Date(timeIntervalSince1970: TimeInterval(payload.exp)),
            email: payload.email,
            preferredUsername: payload.preferred_username
        )
    }
}

#if DEBUG
    extension JWT {
        public static func test(
            token: String = "token",
            expiryDate: Date = Date(),
            email: String? = nil,
            preferredUsername: String? = nil
        ) -> JWT {
            .init(
                token: token,
                expiryDate: expiryDate,
                email: email,
                preferredUsername: preferredUsername
            )
        }
    }
#endif
