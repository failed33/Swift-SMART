//
//  ServerTests.swift
//  SMART-on-FHIR
//
//  Created by Pascal Pfiffner on 6/23/14.
//  2014, SMART Health IT.
//

import Foundation
import XCTest

@testable import SMART

@MainActor
final class ServerIntegrationTests: XCTestCase {
    func testServerInitializationNormalizesAudience() {
        let server = Server(baseURL: URL(string: "https://api.io")!)

        XCTAssertEqual(server.baseURL.absoluteString, "https://api.io/")
        XCTAssertEqual(server.aud, "https://api.io")
    }

    func testMetadataFixtureAvailable() throws {
        let data = try FixtureLoader.data(named: "metadata")
        XCTAssertFalse(data.isEmpty)

        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        let dictionary = try XCTUnwrap(jsonObject as? [String: Any])
        XCTAssertEqual(dictionary["resourceType"] as? String, "CapabilityStatement")
    }
}
