// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacLocalASR",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacLocalASR", targets: ["MacLocalASR"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/sindresorhus/KeyboardShortcuts",
            from: "2.4.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "MacLocalASR",
            dependencies: ["KeyboardShortcuts"],
            path: "MacLocalASR",
            exclude: ["Info.plist"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "MacLocalASR/Info.plist"
                ])
            ]
        )
    ]
)
