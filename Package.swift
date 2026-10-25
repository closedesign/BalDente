// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BalDente",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "CSMC", linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "BalDenteCore", dependencies: ["CSMC"]),
        .executableTarget(name: "smcprobe", dependencies: ["CSMC"]),
        .executableTarget(name: "baldented", dependencies: ["BalDenteCore"]),
        .executableTarget(name: "baldente", dependencies: ["BalDenteCore"]),
        .executableTarget(name: "BalDenteApp", dependencies: ["BalDenteCore"]),
        .testTarget(name: "BalDenteCoreTests", dependencies: ["BalDenteCore"]),
    ]
)
