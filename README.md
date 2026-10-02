# Asteroid Computing: astro-duckdb-xcframework

A Swift package from Asteroid Computing that gives Swift code on macOS the [DuckDB](https://duckdb.org) C API, as a prebuilt, optimised static library.

> [!IMPORTANT]
> **This is not an official DuckDB project.** Asteroid Computing makes and maintains this package. The DuckDB Foundation and DuckDB Labs do not make, maintain, endorse, or support it. Do not send questions or problems about this package to the DuckDB project; [open an issue here](https://github.com/asteroid-computing/astro-duckdb-xcframework/issues) instead.
>
> DuckDB is a trademark of the DuckDB Foundation. This package uses the name only to say which software it contains.

## What it contains

- `CDuckDB.xcframework`: the official DuckDB static libraries from the [DuckDB GitHub release](https://github.com/duckdb/duckdb/releases) (`static-libs-osx-arm64.zip`), merged into one library, with `duckdb.h` and a module map. The code is not changed or compiled again.
- The extensions that the DuckDB release builds in: core functions, Parquet, JSON, ICU, and autocomplete. The TPC-H and TPC-DS data generators are removed.
- The `CDuckDB` Swift module. It is the C API only, with no Swift wrapper.

Platform: macOS 11 or later, Apple silicon (arm64) only.

## Why

When you build DuckDB from source with Swift Package Manager, a clean build takes a long time, and a Debug build of DuckDB is very slow at run time. This package gives you the Release build that DuckDB publishes, in both your Debug and Release builds.

## Use

```swift
dependencies: [
    .package(url: "https://github.com/asteroid-computing/astro-duckdb-xcframework", from: "1.5.6"),
],
targets: [
    .target(name: "MyTarget", dependencies: [
        .product(name: "CDuckDB", package: "astro-duckdb-xcframework"),
    ]),
]
```

```swift
import CDuckDB

var database: duckdb_database?
var connection: duckdb_connection?
duckdb_open(nil, &database)
duckdb_connect(database, &connection)
print(String(cString: duckdb_library_version()))
```

Read the [DuckDB C API documentation](https://duckdb.org/docs/stable/clients/c/overview) for the full API.

## Versions

Each tag of this package has the same number as the DuckDB version it contains. For example, tag `1.5.6` contains DuckDB v1.5.6. The release for each tag has `CDuckDB.xcframework.zip`, and `Package.swift` has its SHA-256 checksum, so Swift Package Manager checks the download.

## Build it yourself

You need Xcode. The script uses only Swift and the Xcode command-line tools.

```bash
swift Scripts/BuildXCFramework.swift 1.5.6
```

The script:

1. Downloads `static-libs-osx-arm64.zip` from the DuckDB release, and stops if its SHA-256 digest is not the pinned digest in the script.
2. Merges the libraries with `libtool`, and makes `build/CDuckDB.xcframework` with `xcodebuild -create-xcframework`.
3. Writes `build/CDuckDB.xcframework.zip` and its checksum.
4. Copies the licence files from the DuckDB source at the same tag into `LICENSES/`.

To test the local build before you publish it:

```bash
ASTRO_DUCKDB_LOCAL=1 swift test
```

To add a new DuckDB version, add its digest from the DuckDB release page to `pinnedDigests` in the script, run the script, put the version and the printed checksum in `Package.swift`, then tag the commit and attach the zip to a release with the same name as the tag.

## Licences

- DuckDB is released under the [MIT License](https://github.com/duckdb/duckdb/blob/main/LICENSE). DuckDB includes third-party code with its own licences. [`LICENSES/`](LICENSES/README.md) has a copy of each licence file from the DuckDB source tree at the packaged version. If you ship an app that uses this package, include these notices.
- The files that Asteroid Computing wrote for this repository (the script, `Package.swift`, and the tests) are released under the [MIT License](LICENSE).
