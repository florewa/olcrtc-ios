// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "OlcrtcParsing",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "OlcrtcParsing", targets: ["OlcrtcParsing"])
    ],
    targets: [
        .target(
            name: "OlcrtcParsing",
            path: "App",
            exclude: [
                "Info.plist",
                "Assets.xcassets",
                "OlcrtcIOSApp.swift",
                "Runtime",
                "Security",
                "Views"
            ],
            sources: ["Models", "Parsing"]
        ),
        .testTarget(
            name: "OlcrtcParsingTests",
            dependencies: ["OlcrtcParsing"],
            path: "Tests"
        )
    ]
)
