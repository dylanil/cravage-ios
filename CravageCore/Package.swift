// swift-tools-version: 5.10
// CravageCore: the protocol maths, crypto, round state machine and transcript.
// Pure Swift + CryptoKit + Foundation. Nothing in here may import UIKit, SwiftUI,
// MultipeerConnectivity or StoreKit - the app target is the only place that touches the OS.
// macOS is listed so that `swift test` runs on the Mac and on CI without a simulator.
import PackageDescription

let package = Package(
    name: "CravageCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CravageCore", targets: ["CravageCore"]),
    ],
    targets: [
        .target(name: "CravageCore"),
        .testTarget(name: "CravageCoreTests", dependencies: ["CravageCore"]),
    ]
)
