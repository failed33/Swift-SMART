//
//  SMARTError.swift
//  Swift-SMART
//

import Foundation

enum SMARTError: LocalizedError {
    case invalidIssuer(String)
    case missingAuthorization
    case configuration(String)
    case generic(String)

    var errorDescription: String? {
        switch self {
        case .invalidIssuer(let issuer):
            return "Invalid SMART issuer: \(issuer)"
        case .missingAuthorization:
            return "Client error, no authorization instance created"
        case .configuration(let message):
            return message
        case .generic(let message):
            return message
        }
    }
}
