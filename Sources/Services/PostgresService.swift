import Foundation
import PostgresNIO
import NIOCore
import NIOSSL
import Logging

final class PostgresService: @unchecked Sendable {
    struct SchemaMetadata {
        let schemas: [SchemaInfo]
        let columnsByTable: [TableRef: [TableColumn]]
    }

    private var connection: PostgresConnection?
    private let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 2)
    private let logger = Logger(label: "drift.postgres")

    var isConnected: Bool { connection != nil }

    func connect(config: SavedConnection) async throws {
        try await disconnect()

        let tls: PostgresConnection.Configuration.TLS
        if config.useSSL {
            var tlsConfig = TLSConfiguration.makeClientConfiguration()
            tlsConfig.certificateVerification = .fullVerification
            tls = .require(try NIOSSLContext(configuration: tlsConfig))
        } else {
            tls = .disable
        }

        var pgConfig = PostgresConnection.Configuration(
            host: config.host,
            port: config.port,
            username: config.username,
            password: config.password.isEmpty ? nil : config.password,
            database: config.database,
            tls: tls
        )
        // SNI is needed for Neon and other cloud providers
        pgConfig.options.tlsServerName = config.host

        do {
            connection = try await PostgresConnection.connect(
                on: eventLoopGroup.next(),
                configuration: pgConfig,
                id: 1,
                logger: logger
            )
            // Verify connection
            _ = try await executeRaw("SELECT 1")
        } catch {
            // PostgresNIO hides details by default — expose them for debugging
            let detail = String(reflecting: error)
            throw DriftError.connectionFailed(detail)
        }
    }

    func disconnect() async throws {
        if let conn = connection {
            try await conn.close()
            connection = nil
        }
    }

    func fetchSchemas() async throws -> [SchemaInfo] {
        // Get all user schemas
        let schemasResult = try await executeRaw(
            "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast') ORDER BY schema_name"
        )
        var schemas: [SchemaInfo] = []
        for row in schemasResult.rows {
            guard let schemaName = row[0] else { continue }
            let tablesResult = try await executeRaw(
                "SELECT table_name FROM information_schema.tables WHERE table_schema = '\(escapeSql(schemaName))' AND table_type = 'BASE TABLE' ORDER BY table_name"
            )
            let tables = tablesResult.rows.compactMap { $0[0] }
            if !tables.isEmpty {
                schemas.append(SchemaInfo(name: schemaName, tables: tables))
            }
        }
        return schemas
    }

    func fetchSchemaMetadata() async throws -> SchemaMetadata {
        let tablesResult = try await executeRaw(
            """
            SELECT table_schema, table_name
            FROM information_schema.tables
            WHERE table_schema NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
              AND table_type = 'BASE TABLE'
            ORDER BY table_schema, table_name
            """
        )

        let columnsResult = try await executeRaw(
            """
            SELECT
              c.table_schema,
              c.table_name,
              c.column_name,
              c.data_type,
              c.is_nullable,
              c.ordinal_position,
              CASE WHEN pk.column_name IS NOT NULL THEN 'YES' ELSE 'NO' END AS is_primary_key
            FROM information_schema.columns c
            LEFT JOIN (
              SELECT DISTINCT
                kcu.table_schema,
                kcu.table_name,
                kcu.column_name
              FROM information_schema.table_constraints tc
              JOIN information_schema.key_column_usage kcu
                ON tc.constraint_name = kcu.constraint_name
               AND tc.table_schema = kcu.table_schema
               AND tc.table_name = kcu.table_name
              WHERE tc.constraint_type = 'PRIMARY KEY'
            ) pk
              ON c.table_schema = pk.table_schema
             AND c.table_name = pk.table_name
             AND c.column_name = pk.column_name
            WHERE c.table_schema NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
            ORDER BY c.table_schema, c.table_name, c.ordinal_position
            """
        )

        var tablesBySchema: [String: [String]] = [:]
        for row in tablesResult.rows {
            guard row.count >= 2,
                  let schema = row[0],
                  let table = row[1] else { continue }
            tablesBySchema[schema, default: []].append(table)
        }

        var columnsByTable: [TableRef: [TableColumn]] = [:]
        for row in columnsResult.rows {
            guard row.count >= 7,
                  let schema = row[0],
                  let table = row[1],
                  let name = row[2],
                  let dataType = row[3] else { continue }

            let ref = TableRef(schema: schema, table: table)
            let column = TableColumn(
                name: name,
                dataType: dataType,
                isNullable: row[4] == "YES",
                isPrimaryKey: row[6] == "YES",
                ordinalPosition: Int(row[5] ?? "0") ?? 0
            )
            columnsByTable[ref, default: []].append(column)
        }

        let schemas = tablesBySchema
            .keys
            .sorted()
            .map { schemaName in
                SchemaInfo(name: schemaName, tables: tablesBySchema[schemaName] ?? [])
            }

        return SchemaMetadata(schemas: schemas, columnsByTable: columnsByTable)
    }

    func fetchColumns(schema: String, table: String) async throws -> [TableColumn] {
        // Simple column query — no subquery
        let colResult = try await executeRaw(
            "SELECT column_name, data_type, is_nullable, ordinal_position FROM information_schema.columns WHERE table_schema = '\(escapeSql(schema))' AND table_name = '\(escapeSql(table))' ORDER BY ordinal_position"
        )

        // Separate PK query
        let pkResult = try await executeRaw(
            "SELECT kcu.column_name FROM information_schema.table_constraints tc JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema WHERE tc.table_schema = '\(escapeSql(schema))' AND tc.table_name = '\(escapeSql(table))' AND tc.constraint_type = 'PRIMARY KEY'"
        )
        let pkColumns = Set(pkResult.rows.compactMap { $0[0] })

        return colResult.rows.compactMap { row in
            guard let name = row[0], let dataType = row[1] else { return nil }
            return TableColumn(
                name: name,
                dataType: dataType,
                isNullable: row[2] == "YES",
                isPrimaryKey: pkColumns.contains(name),
                ordinalPosition: Int(row[3] ?? "0") ?? 0
            )
        }
    }

    func fetchTableData(
        schema: String,
        table: String,
        columns: [TableColumn],
        limit: Int = 500,
        offset: Int = 0,
        sortColumn: String? = nil,
        sortDescending: Bool = false,
        filters: [String: String] = [:]
    ) async throws -> QueryResultData {
        let colCasts = columns.map { "\"\($0.name)\"::text AS \"\($0.name)\"" }.joined(separator: ", ")
        var sql = "SELECT \(colCasts) FROM \"\(schema)\".\"\(table)\""

        // Filters
        var conditions: [String] = []
        for (col, value) in filters where !value.isEmpty {
            conditions.append("\"\(col)\"::text ILIKE '%\(value.replacingOccurrences(of: "'", with: "''"))%'")
        }
        if !conditions.isEmpty {
            sql += " WHERE " + conditions.joined(separator: " AND ")
        }

        // Sort
        if let sortCol = sortColumn {
            sql += " ORDER BY \"\(sortCol)\" \(sortDescending ? "DESC" : "ASC") NULLS LAST"
        }

        sql += " LIMIT \(limit) OFFSET \(offset)"

        // Get total count
        var countSQL = "SELECT COUNT(*) FROM \"\(schema)\".\"\(table)\""
        if !conditions.isEmpty {
            countSQL += " WHERE " + conditions.joined(separator: " AND ")
        }

        let start = Date()
        let data = try await executeRaw(sql)
        let countResult = try await executeRaw(countSQL)
        let elapsed = Date().timeIntervalSince(start)

        var totalCount = 0
        if let firstRow = countResult.rows.first, let firstVal = firstRow.first, let val = firstVal {
            totalCount = Int(val) ?? 0
        }
        // Fallback: if count query returned 0 but we got rows, use rows count
        if totalCount == 0 && !data.rows.isEmpty {
            totalCount = data.rows.count
        }

        return QueryResultData(
            columns: columns.map { ColumnInfo(name: $0.name, dataType: $0.dataType) },
            rows: data.rows,
            rowCount: totalCount,
            executionTime: elapsed,
            truncated: totalCount > offset + limit
        )
    }

    func executeSQL(_ sql: String) async throws -> QueryResultData {
        let start = Date()
        let result = try await executeRaw(sql)
        let elapsed = Date().timeIntervalSince(start)
        return QueryResultData(
            columns: result.columns,
            rows: result.rows,
            rowCount: result.rows.count,
            executionTime: elapsed,
            truncated: false
        )
    }

    func globalSearch(schema: String, table: String, columns: [TableColumn], query: String, limit: Int = 100) async throws -> QueryResultData {
        let escapedQuery = query.replacingOccurrences(of: "'", with: "''")
        let colCasts = columns.map { "\"\($0.name)\"::text AS \"\($0.name)\"" }.joined(separator: ", ")
        let conditions = columns.map { "\"\($0.name)\"::text ILIKE '%\(escapedQuery)%'" }.joined(separator: " OR ")

        let sql = "SELECT \(colCasts) FROM \"\(schema)\".\"\(table)\" WHERE \(conditions) LIMIT \(limit)"
        let start = Date()
        let result = try await executeRaw(sql)
        let elapsed = Date().timeIntervalSince(start)

        return QueryResultData(
            columns: columns.map { ColumnInfo(name: $0.name, dataType: $0.dataType) },
            rows: result.rows,
            rowCount: result.rows.count,
            executionTime: elapsed,
            truncated: result.rows.count >= limit
        )
    }

    // MARK: - Internal

    private func executeRaw(_ sql: String) async throws -> QueryResultData {
        guard let connection else { throw DriftError.notConnected }

        let rows = try await connection.query(PostgresQuery(unsafeSQL: sql), logger: logger)

        var columns: [ColumnInfo] = []
        var resultRows: [[String?]] = []

        for try await row in rows {
            let view = row.makeRandomAccess()
            if columns.isEmpty {
                for i in 0..<view.count {
                    columns.append(ColumnInfo(
                        name: view[i].columnName,
                        dataType: "\(view[i].dataType)"
                    ))
                }
            }

            var rowValues: [String?] = []
            for i in 0..<view.count {
                let cell = view[i]
                if cell.bytes == nil {
                    rowValues.append(nil)
                } else {
                    rowValues.append(decodeCell(cell))
                }
            }
            resultRows.append(rowValues)
        }

        return QueryResultData(
            columns: columns,
            rows: resultRows,
            rowCount: resultRows.count,
            executionTime: 0,
            truncated: false
        )
    }

    private func decodeCell(_ cell: PostgresCell) -> String? {
        guard cell.bytes != nil else { return nil }

        // Decode based on actual PostgreSQL type — don't guess
        switch cell.dataType {
        case .text, .varchar, .name, .bpchar, .json, .jsonb, .xml:
            return (try? cell.decode(String.self, context: .default)) ?? "[text decode failed]"

        case .int2, .int4, .int8, .oid:
            if let i = try? cell.decode(Int.self, context: .default) { return String(i) }

        case .float4:
            if let f = try? cell.decode(Float.self, context: .default) { return String(f) }

        case .float8, .numeric:
            if let d = try? cell.decode(Double.self, context: .default) { return String(d) }

        case .bool:
            if let b = try? cell.decode(Bool.self, context: .default) { return b ? "true" : "false" }

        case .uuid:
            if let u = try? cell.decode(UUID.self, context: .default) { return u.uuidString }

        case .timestamp, .timestamptz:
            if let d = try? cell.decode(Date.self, context: .default) {
                let fmt = ISO8601DateFormatter()
                fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return fmt.string(from: d)
            }

        case .date:
            if let d = try? cell.decode(Date.self, context: .default) {
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd"
                return fmt.string(from: d)
            }

        case .bytea:
            return "[bytea]"

        default:
            // Try String as last resort
            if let s = try? cell.decode(String.self, context: .default) { return s }
        }

        // Final fallback — show type name for unknown binary data
        return "[\(cell.dataType)]"
    }

    private func escapeSql(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    deinit {
        try? eventLoopGroup.syncShutdownGracefully()
    }
}
