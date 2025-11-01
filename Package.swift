// swift-tools-version:5.5
//  Package.swift
//
//  Created by Dave Carlson on 8/8/19.

import PackageDescription

let package = Package(
    name: "SMART",
    platforms: [
        .macOS(.v12), .iOS(.v13),
    ],
    products: [
        .library(
            name: "SMART",
            targets: ["SMART"])
    ],
    dependencies: [
        //.package(url: "https://github.com/smart-on-fhir/Swift-FHIR", "4.2.0"..<"5.0.0"),
        .package(url: "https://github.com/p2/OAuth2", "5.1.0"..<"6.0.0"),
        .package(
            url: "https://github.com/pointfreeco/combine-schedulers", .upToNextMajor(from: "1.0.2")),
        .package(
            url: "https://github.com/apple/FHIRModels.git",
            .upToNextMajor(from: "0.7.0")),

    ],
    targets: [
        .target(
            name: "SMART",
            dependencies: [
                .product(name: "OAuth2", package: "OAuth2"),
                .product(name: "ModelsR5", package: "FHIRModels"),
                .product(name: "CombineSchedulers", package: "combine-schedulers"),
                "FHIRClient",
                "HTTPClient",
                "HTTPClientLive",
            ],
            path: "Sources",
            exclude: [
                "FHIRClient",
                "HTTPClient",
                "HTTPClientLive",
            ],
            sources: [
                "SMART", "Client", "helpers",
            ]),

        .target(
            name: "FHIRClient",
            dependencies: [
                "HTTPClient",
                .product(name: "ModelsR5", package: "FHIRModels"),
                .product(name: "CombineSchedulers", package: "combine-schedulers"),
            ],
            path: "Sources/FHIRClient",
            exclude: [
                "Resources"
            ]
        ),
        .target(
            name: "HTTPClient",
            dependencies: [],
            path: "Sources/HTTPClient",
            exclude: [
                "Resources"
            ]
        ),
        .target(
            name: "HTTPClientLive",
            dependencies: [
                "HTTPClient"
            ],
            path: "Sources/HTTPClientLive",
            exclude: [
                "Resources"
            ]
        ),
        .testTarget(
            name: "SMARTTests",
            dependencies: [
                "SMART",
                "FHIRClient",
                "HTTPClient",
                .product(name: "ModelsR5", package: "FHIRModels")
            ],
            path: "Tests",
            exclude: [
                "strategy",
                "Info.plist"
            ],
            resources: [
                .process("Fixtures")
            ]
        ),
    ]
)
