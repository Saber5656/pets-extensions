// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "typing-with-my-pets",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TypingWithMyPets", targets: ["TypingWithMyPets"])
    ],
    dependencies: [],
    targets: [
        .target(name: "TypingWithMyPetsCore"),
        .executableTarget(
            name: "TypingWithMyPets",
            dependencies: ["TypingWithMyPetsCore"]
        ),
        .testTarget(
            name: "TypingWithMyPetsCoreTests",
            dependencies: ["TypingWithMyPetsCore"]
        )
    ]
)
