// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "CompanionRuntime",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(
      name: "CompanionRuntime",
      targets: ["CompanionRuntime"]
    )
  ],
  targets: [
    .target(name: "CompanionRuntime"),
    .testTarget(
      name: "CompanionRuntimeTests",
      dependencies: ["CompanionRuntime"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
