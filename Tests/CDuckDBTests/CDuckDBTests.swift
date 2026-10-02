import CDuckDB
import Foundation
import XCTest

/// Checks that the packaged library links, runs queries, and includes the Parquet and JSON extensions.
final class CDuckDBTests: XCTestCase {
    private var database: duckdb_database?
    private var connection: duckdb_connection?

    override func setUpWithError() throws {
        XCTAssertEqual(duckdb_open(nil, &database), DuckDBSuccess)
        XCTAssertEqual(duckdb_connect(database, &connection), DuckDBSuccess)
    }

    override func tearDown() {
        duckdb_disconnect(&connection)
        duckdb_close(&database)
    }

    func testLibraryVersionMatchesPackage() {
        XCTAssertEqual(String(cString: duckdb_library_version()), "v1.5.6")
    }

    func testRunsQuery() throws {
        XCTAssertEqual(try firstBigint("SELECT sum(range)::BIGINT FROM range(1000)"), 499_500)
    }

    func testParquetExtensionIsLinked() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "CDuckDBTests-\(UUID().uuidString).parquet").path(percentEncoded: false)
        defer { try? FileManager.default.removeItem(atPath: file) }
        try execute("COPY (SELECT range AS n FROM range(10)) TO '\(file)' (FORMAT parquet)")
        XCTAssertEqual(try firstBigint("SELECT count(*)::BIGINT FROM read_parquet('\(file)')"), 10)
    }

    func testJSONExtensionIsLinked() throws {
        XCTAssertEqual(try firstBigint("SELECT json_array_length('[1, 2, 3]')::BIGINT"), 3)
    }

    private func execute(_ sql: String) throws {
        var result = duckdb_result()
        defer { duckdb_destroy_result(&result) }
        guard duckdb_query(connection, sql, &result) == DuckDBSuccess else {
            throw QueryError(message: duckdb_result_error(&result).map { String(cString: $0) } ?? "Unknown error")
        }
    }

    private func firstBigint(_ sql: String) throws -> Int64? {
        var result = duckdb_result()
        defer { duckdb_destroy_result(&result) }
        guard duckdb_query(connection, sql, &result) == DuckDBSuccess else {
            throw QueryError(message: duckdb_result_error(&result).map { String(cString: $0) } ?? "Unknown error")
        }
        guard let chunk = duckdb_fetch_chunk(result) else { return nil }
        var owned: duckdb_data_chunk? = chunk
        defer { duckdb_destroy_data_chunk(&owned) }
        let vector = duckdb_data_chunk_get_vector(chunk, 0)
        return duckdb_vector_get_data(vector)?.assumingMemoryBound(to: Int64.self).pointee
    }

    private struct QueryError: Error {
        let message: String
    }
}
