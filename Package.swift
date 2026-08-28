// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HookyBar",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "HookyBar", targets: ["HookyBar"])],
    dependencies: [
        .package(url: "https://github.com/ejbills/mediaremote-adapter.git", revision: "5b6afde3f501a3da567e23bf7f23d562938a1809")
    ],
    targets: [
        .executableTarget(
            name: "HookyBar",
            dependencies: [
                .product(name: "MediaRemoteAdapter", package: "mediaremote-adapter")
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "HookyBarTests",
            dependencies: [
                "HookyBar",
                .product(name: "MediaRemoteAdapter", package: "mediaremote-adapter")
            ]
        )
    ]
)
