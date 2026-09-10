// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HerdrKit",
    platforms: [.macOS(.v14), .iOS(.v18)],
    products: [
        .library(name: "HerdrKit", targets: ["HerdrKit"])
    ],
    dependencies: [
        .package(path: "../HerdrTailcat")
    ],
    targets: [
        .target(
            name: "HerdrKit",
            dependencies: [
                .product(name: "HerdrTailcat", package: "HerdrTailcat")
            ],
            linkerSettings: [.linkedFramework("Security")]
        ),
        .testTarget(name: "HerdrKitTests", dependencies: ["HerdrKit"])
    ]
)
