// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FinderConvertCore",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "FinderConvertCore",
            targets: ["FinderConvertCore"]
        ),
    ],
    targets: [
        .systemLibrary(
            name: "CLame",
            path: "Sources/CLame"
        ),
        .systemLibrary(
            name: "CWebP",
            path: "Sources/CWebP"
        ),
        .target(
            name: "FinderConvertCore",
            dependencies: ["CLame", "CWebP"],
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L\(Context.packageDirectory)/Sources/CLame",
                    "-lmp3lame",
                    "-L\(Context.packageDirectory)/Sources/CWebP",
                    "-lwebp", "-lsharpyuv",
                ]),
            ]
        ),
    ]
)
