//
//  FHIROperations.swift
//  Swift-SMART
//
//  Common FHIRClientOperation helpers used by SMART Client APIs.
//

import FHIRClient
import Foundation
import HTTPClient

struct RawFHIRRequestOperation: FHIRClientOperation {
    typealias Value = FHIRClient.Response

    private let path: String
    private let method: HTTPMethod
    private let headers: [String: String]
    private let body: Data?

    init(
        path: String,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.path = path
        self.method = method
        self.headers = headers
        self.body = body
    }

    var relativeUrlString: String? {
        path
    }

    var httpHeaders: [String: String] {
        headers
    }

    var httpMethod: HTTPMethod {
        method
    }

    var httpBody: Data? {
        body
    }

    func handle(response: FHIRClient.Response) throws -> FHIRClient.Response {
        response
    }
}

struct DecodingFHIRRequestOperation<Decoded: Decodable>: FHIRClientOperation {
    typealias Value = Decoded

    private let request: RawFHIRRequestOperation
    private let decoder: JSONDecoder

    init(
        path: String,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: Data? = nil,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.request = RawFHIRRequestOperation(
            path: path, method: method, headers: headers, body: body)
        self.decoder = decoder
    }

    var relativeUrlString: String? {
        request.relativeUrlString
    }

    var httpHeaders: [String: String] {
        request.httpHeaders
    }

    var httpMethod: HTTPMethod {
        request.httpMethod
    }

    var httpBody: Data? {
        request.httpBody
    }

    func handle(response: FHIRClient.Response) throws -> Decoded {
        try decoder.decode(Decoded.self, from: response.body)
    }
}
