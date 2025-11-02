//
//  SMART_on_FHIR_iOSTests.swift
//  SMART-on-FHIR-iOSTests
//
//  Created by Pascal Pfiffner on 6/20/14.
//  2014, SMART Platforms.
//

import SMART
import XCTest

final class ClientIntegrationTests: XCTestCase {
    func testClientInitializationUsesNormalizedServerURL() {
        let baseURL = URL(string: "https://api.io")!
        let client = Client(baseURL: baseURL, settings: ["redirect": "oauth://callback"])

        XCTAssertEqual(client.server.baseURL.absoluteString, "https://api.io/")
        XCTAssertEqual(client.server.aud, "https://api.io")
    }
}
