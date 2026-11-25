// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "tom_media_extract_probe",
  platforms: [.iOS("13.0"), .macOS("10.15")],
  products: [
    .library(name: "tom-media-extract-probe", targets: ["tom_media_extract_probe"])
  ],
  dependencies: [],
  targets: [
    .target(name: "tom_media_extract_probe", dependencies: [], resources: [])
  ]
)
