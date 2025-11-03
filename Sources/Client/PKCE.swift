//
//  PKCE.swift
//  Swift-SMART
//
//  Implements Proof Key for Code Exchange as required by SMART App Launch.
//

import Foundation

#if canImport(CryptoKit)
    import CryptoKit
#elseif canImport(Crypto)
    import Crypto
#endif

/// Container representing a PKCE challenge pair.
public struct PKCE {
    public let codeVerifier: String
    public let codeChallenge: String
    public let method: String

    private init(codeVerifier: String, codeChallenge: String, method: String) {
        self.codeVerifier = codeVerifier
        self.codeChallenge = codeChallenge
        self.method = method
    }

    /// Generates a new PKCE pair using the S256 method.
    public static func generate(length: Int = 64) -> PKCE {
        let verifier = generateCodeVerifier(length: length)
        let challenge = deriveCodeChallenge(from: verifier)
        return PKCE(codeVerifier: verifier, codeChallenge: challenge, method: "S256")
    }

    /// Generates a random code verifier using the allowed character set.
    public static func generateCodeVerifier(length: Int = 64) -> String {
        let boundedLength = max(43, min(length, 128))
        let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

        var verifier = String()
        verifier.reserveCapacity(boundedLength)
        for _ in 0..<boundedLength {
            guard let scalar = characters.randomElement() else {
                continue
            }
            verifier.append(scalar)
        }
        return verifier
    }

    /// Derives the code challenge using SHA-256 and base64url encoding.
    public static func deriveCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let digest = sha256(data: data)
        return base64URLEncode(data: digest)
    }

    private static func sha256(data: Data) -> Data {
        #if canImport(CryptoKit)
            let hash = CryptoKit.SHA256.hash(data: data)
            return Data(hash)
        #elseif canImport(Crypto)
            let hash = Crypto.SHA256.hash(data: data)
            return Data(hash)
        #else
            preconditionFailure("SHA-256 is not available on this platform")
        #endif
    }

    private static func base64URLEncode(data: Data) -> String {
        var encoded = data.base64EncodedString()
        encoded = encoded.replacingOccurrences(of: "+", with: "-")
        encoded = encoded.replacingOccurrences(of: "/", with: "_")
        encoded = encoded.replacingOccurrences(of: "=", with: "")
        return encoded
    }
}
