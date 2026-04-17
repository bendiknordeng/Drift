import Foundation

// MARK: - Connection

struct SavedConnection: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var host: String
    var port: Int
    var username: String
    var password: String
    var database: String
    var useSSL: Bool
    var neonProjectId: String?
    var neonBranchId: String?

    var displayName: String {
        if !name.isEmpty { return name }
        return "\(database)@\(host)"
    }

    var connectionString: String {
        let ssl = useSSL ? "?sslmode=require" : ""
        let pass = password.isEmpty ? "" : ":\(password)"
        return "postgresql://\(username)\(pass)@\(host):\(port)/\(database)\(ssl)"
    }

    static func fromConnectionString(_ str: String) -> SavedConnection? {
        guard let url = URL(string: str.replacingOccurrences(of: "postgres://", with: "postgresql://")) else { return nil }
        // URLComponents handles percent-decoding of user/password
        let components = URLComponents(string: str.replacingOccurrences(of: "postgres://", with: "postgresql://"))
        let host = url.host ?? "localhost"
        let port = url.port ?? 5432
        let username = components?.user ?? url.user ?? "postgres"
        let password = components?.password ?? url.password ?? ""
        var database = url.path
        if database.hasPrefix("/") { database = String(database.dropFirst()) }
        if database.isEmpty { database = "postgres" }
        let useSSL = str.contains("sslmode=require") || str.contains("neon.tech")

        return SavedConnection(
            name: "",
            host: host,
            port: port,
            username: username,
            password: password,
            database: database,
            useSSL: useSSL
        )
    }
}

// MARK: - Schema & Table

struct SchemaInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    var tables: [String]
}

struct TableRef: Hashable, Equatable {
    let schema: String
    let table: String

    var fullName: String { "\(schema).\(table)" }
}

struct TableColumn: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let dataType: String
    let isNullable: Bool
    let isPrimaryKey: Bool
    let ordinalPosition: Int
}

// MARK: - Tabs

struct TableTab: Identifiable, Equatable {
    let id: TableRef
    let ref: TableRef
    var isPinned: Bool

    init(ref: TableRef, isPinned: Bool = false) {
        self.id = ref
        self.ref = ref
        self.isPinned = isPinned
    }
}

// MARK: - Query Results

struct QueryResultData: Identifiable {
    let id = UUID()
    let columns: [ColumnInfo]
    let rows: [[String?]]
    let rowCount: Int
    let executionTime: TimeInterval
    let truncated: Bool

    static let empty = QueryResultData(columns: [], rows: [], rowCount: 0, executionTime: 0, truncated: false)
}

struct ColumnInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let dataType: String
}

// MARK: - Neon

struct NeonOrganization: Identifiable, Codable, Hashable {
    let id: String
    let name: String
}

struct NeonProject: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let region_id: String?
    let created_at: String?
}

struct NeonBranch: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let parent_id: String?
    let current_state: String?
    let created_at: String?
    let updated_at: String?
}

struct NeonDatabase: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let owner_name: String
}

struct NeonRole: Identifiable, Codable, Hashable {
    let name: String
    var id: String { name }
}

struct NeonConnectionURI: Codable {
    let uri: String
}

// MARK: - LLM

struct LLMMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    var sql: String?
    var result: QueryResultData?

    enum Role {
        case user
        case assistant
    }
}

// MARK: - UI State

enum ContentTab: String, CaseIterable {
    case browser = "Browser"
    case sql = "SQL"
}

// MARK: - Errors

enum DriftError: LocalizedError {
    case notConnected
    case connectionFailed(String)
    case queryFailed(String)
    case neonAPIError(String)
    case llmError(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to a database"
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .queryFailed(let msg): return "Query failed: \(msg)"
        case .neonAPIError(let msg): return "Neon API error: \(msg)"
        case .llmError(let msg): return "LLM error: \(msg)"
        }
    }
}
