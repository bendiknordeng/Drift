import Foundation

final class LLMService {
    var apiKey: String = ""
    var model: String = "claude-sonnet-4-20250514"

    var isConfigured: Bool { !apiKey.isEmpty }

    func generateSQL(userQuery: String, schemaContext: String) async throws -> LLMResponse {
        guard isConfigured else { throw DriftError.llmError("API key not configured") }

        let systemPrompt = """
            You are a PostgreSQL expert. Given a database schema and a natural language question,
            generate the appropriate SQL query. Return ONLY a JSON object with two fields:
            - "sql": the SQL query string
            - "explanation": a brief one-line explanation of what the query does

            Database schema:
            \(schemaContext)
            """

        let payload: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userQuery]
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: payload)

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DriftError.llmError("API error: \(body)")
        }

        let apiResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        guard let textContent = apiResponse.content.first?.text else {
            throw DriftError.llmError("Empty response")
        }

        // Parse the JSON from the response text
        let cleaned = textContent
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let jsonData = cleaned.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let sql = json["sql"] as? String {
            return LLMResponse(
                sql: sql,
                explanation: json["explanation"] as? String ?? ""
            )
        }

        // Fallback: treat whole response as SQL
        return LLMResponse(sql: textContent, explanation: "")
    }

    func buildSchemaContext(schemas: [SchemaInfo], columns: [TableRef: [TableColumn]]) -> String {
        var ctx = ""
        for schema in schemas {
            for table in schema.tables {
                let ref = TableRef(schema: schema.name, table: table)
                ctx += "\(schema.name).\(table):\n"
                if let cols = columns[ref] {
                    for col in cols {
                        let pk = col.isPrimaryKey ? " PK" : ""
                        let nullable = col.isNullable ? " NULL" : " NOT NULL"
                        ctx += "  - \(col.name) \(col.dataType)\(nullable)\(pk)\n"
                    }
                }
                ctx += "\n"
            }
        }
        return ctx
    }

    struct LLMResponse {
        let sql: String
        let explanation: String
    }

    // MARK: - Claude API Types

    private struct ClaudeResponse: Codable {
        let content: [ContentBlock]
    }

    private struct ContentBlock: Codable {
        let type: String
        let text: String?
    }
}
