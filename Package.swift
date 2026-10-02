// swift-tools-version: 5.9

import PackageDescription

// The DuckDB version, and the checksum of CDuckDB.xcframework.zip on the matching GitHub release.
// Scripts/BuildXCFramework.swift prints both values.
let version = "1.5.6"
let checksum = "dfeaca162cf57c631bd91353a990e14cfb1ee45dd151af443c5931a822022117"

// ASTRO_DUCKDB_LOCAL=1 uses build/CDuckDB.xcframework from the script instead of the release download,
// for example to test a new build before it is published.
let useLocalBuild = Context.environment["ASTRO_DUCKDB_LOCAL"] == "1"

let package = Package(
    name: "astro-duckdb-xcframework",
    platforms: [
        .macOS(.v11),
    ],
    products: [
        .library(name: "CDuckDB", targets: ["CDuckDB"]),
    ],
    targets: [
        useLocalBuild
            ? .binaryTarget(name: "CDuckDB", path: "build/CDuckDB.xcframework")
            : .binaryTarget(
                name: "CDuckDB",
                url: "https://github.com/asteroid-computing/astro-duckdb-xcframework/releases/download/\(version)/CDuckDB.xcframework.zip",
                checksum: checksum
            ),
        .testTarget(name: "CDuckDBTests", dependencies: ["CDuckDB"]),
    ]
)
