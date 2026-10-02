#!/usr/bin/env swift
// Packages DuckDB's official macOS static libraries as CDuckDB.xcframework.
//
// Usage: swift Scripts/BuildXCFramework.swift [version]
//
// The script downloads static-libs-osx-arm64.zip from DuckDB's GitHub release,
// checks it against a pinned SHA-256 digest,
// merges the libraries into one archive, adds duckdb.h and a module map,
// and writes build/CDuckDB.xcframework and build/CDuckDB.xcframework.zip.
// It also collects the licence files from DuckDB's source tree at the same tag into LICENSES/.
// It never changes Package.swift; it prints the checksum to put there.

import CryptoKit
import Foundation

/// SHA-256 digests of `static-libs-osx-arm64.zip`, as published on each DuckDB release.
/// Add a version only after you compare the digest with the one on GitHub.
let pinnedDigests: [String: String] = [
    "1.5.6": "e77c382fba15e3f5c0b3265d12e3a4de534699fdb91bcc9d10d4a857a58103d5",
]

/// Benchmark data generators in the release that apps do not need.
/// Do not add libraries that the generated extension loader refers to (for example autocomplete),
/// or apps fail to link.
let excludedLibraries: Set<String> = [
    "libtpcds_extension.a",
    "libtpch_extension.a",
]

/// Licence files in DuckDB's source tree that do not describe code in the packaged libraries.
let excludedLicensePrefixes = ["data/", "tools/", "extension/tpch/", "extension/tpcds/"]

let moduleMap = """
    module CDuckDB {
        header "duckdb.h"
        link "c++"
        export *
    }

    """

struct ScriptError: Error, CustomStringConvertible {
    let description: String
}

let root = URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)
let build = root.appending(path: "build", directoryHint: .isDirectory)

@discardableResult
func run(_ tool: String, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/env")
    process.arguments = [tool] + arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let text = String(decoding: data, as: UTF8.self)
    guard process.terminationStatus == 0 else {
        throw ScriptError(description: "\(tool) failed with status \(process.terminationStatus):\n\(text)")
    }
    return text
}

func sha256(of url: URL) throws -> String {
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func download(_ remote: URL, to local: URL) async throws {
    let (temporary, response) = try await URLSession.shared.download(from: remote)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw ScriptError(description: "Download of \(remote) failed: \(response)")
    }
    try? FileManager.default.removeItem(at: local)
    try FileManager.default.moveItem(at: temporary, to: local)
}

func fresh(_ directory: URL) throws -> URL {
    try? FileManager.default.removeItem(at: directory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

/// Copies the licence files at `tag` into `LICENSES/`, one file per source path.
func collectLicenses(tag: String) async throws -> Int {
    struct Tree: Decodable {
        struct Entry: Decodable {
            let path: String
            let type: String
        }
        let tree: [Entry]
        let truncated: Bool
    }
    let treeURL = URL(string: "https://api.github.com/repos/duckdb/duckdb/git/trees/\(tag)?recursive=1")!
    let (data, _) = try await URLSession.shared.data(from: treeURL)
    let tree = try JSONDecoder().decode(Tree.self, from: data)
    guard !tree.truncated else { throw ScriptError(description: "The GitHub tree listing for \(tag) is truncated.") }

    let licensePattern = #/(^|/)(LICEN[CS]E|COPYING|NOTICES?)[^/]*$/#.ignoresCase()
    let paths = tree.tree
        .filter { $0.type == "blob" && $0.path.contains(licensePattern) }
        .map(\.path)
        .filter { path in !excludedLicensePrefixes.contains { path.hasPrefix($0) } }
        .sorted()

    let licenses = try fresh(root.appending(path: "LICENSES", directoryHint: .isDirectory))
    var index = "# Licences of DuckDB \(tag) and the code it bundles\n\nCollected from https://github.com/duckdb/duckdb/tree/\(tag) by `Scripts/BuildXCFramework.swift`.\n\n"
    for path in paths {
        let raw = URL(string: "https://raw.githubusercontent.com/duckdb/duckdb/\(tag)/\(path)")!
        let name = path.replacingOccurrences(of: "/", with: "__")
        try await download(raw, to: licenses.appending(path: name))
        index += "- [`\(path)`](\(name))\n"
    }
    try Data(index.utf8).write(to: licenses.appending(path: "README.md"))
    return paths.count
}

let version = CommandLine.arguments.dropFirst().first ?? pinnedDigests.keys.sorted().last!
guard let expectedDigest = pinnedDigests[version] else {
    throw ScriptError(description: "Version \(version) is not pinned. Add its digest to pinnedDigests first.")
}
let tag = "v\(version)"

print("Packaging DuckDB \(version)")
let work = try fresh(build.appending(path: "work", directoryHint: .isDirectory))
let archive = work.appending(path: "static-libs-osx-arm64.zip")
try await download(URL(string: "https://github.com/duckdb/duckdb/releases/download/\(tag)/static-libs-osx-arm64.zip")!, to: archive)
let digest = try sha256(of: archive)
guard digest == expectedDigest else {
    throw ScriptError(description: "Digest mismatch for \(archive.lastPathComponent): expected \(expectedDigest), got \(digest).")
}
print("  verified \(archive.lastPathComponent) (sha256 \(digest))")

let extracted = work.appending(path: "static", directoryHint: .isDirectory)
try run("ditto", ["-x", "-k", archive.path(percentEncoded: false), extracted.path(percentEncoded: false)])
let libraries = try FileManager.default.contentsOfDirectory(atPath: extracted.path(percentEncoded: false))
    .filter { $0.hasSuffix(".a") && !excludedLibraries.contains($0) }
    .sorted()
print("  merging \(libraries.count) libraries")
let merged = work.appending(path: "libduckdb.a")
try run("libtool", ["-static", "-no_warning_for_no_symbols", "-o", merged.path(percentEncoded: false)] + libraries.map { extracted.appending(path: $0).path(percentEncoded: false) })

let headers = try fresh(work.appending(path: "Headers", directoryHint: .isDirectory))
try FileManager.default.copyItem(at: extracted.appending(path: "duckdb.h"), to: headers.appending(path: "duckdb.h"))
try Data(moduleMap.utf8).write(to: headers.appending(path: "module.modulemap"))

// No directory hint: xcodebuild rejects an output path that ends in a slash.
let framework = build.appending(path: "CDuckDB.xcframework", directoryHint: .notDirectory)
try? FileManager.default.removeItem(at: framework)
try run("xcodebuild", ["-create-xcframework", "-library", merged.path(percentEncoded: false), "-headers", headers.path(percentEncoded: false), "-output", framework.path(percentEncoded: false)])

let zip = build.appending(path: "CDuckDB.xcframework.zip")
try? FileManager.default.removeItem(at: zip)
try run("ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", framework.path(percentEncoded: false), zip.path(percentEncoded: false)])
let checksum = try sha256(of: zip)
try Data("\(checksum)  CDuckDB.xcframework.zip\n".utf8).write(to: build.appending(path: "CDuckDB.xcframework.zip.sha256"))

let licenseCount = try await collectLicenses(tag: tag)
print("  collected \(licenseCount) licence files into LICENSES/")

print("""

    Done.
      build/CDuckDB.xcframework
      build/CDuckDB.xcframework.zip
      checksum: \(checksum)

    Put this in Package.swift:
      let version = "\(version)"
      let checksum = "\(checksum)"
    """)
