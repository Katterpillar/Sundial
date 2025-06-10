//swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "Sundial",
    platforms: [
      .iOS(.v13)
    ],
    products: [
      .library(name: "Sundial", targets: ["Sundial"])
    ],
    dependencies: [
      .package(url: "https://github.com/Katterpillar/Astrolabe.git", branch: "master")
    ],
    targets: [
      .target(name: "Sundial", dependencies: ["Astrolabe"], path: "./Sources")
    ],
    swiftLanguageVersions: [.v5]
)
