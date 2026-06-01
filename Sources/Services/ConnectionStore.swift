import Foundation

final class ConnectionStore {
    private let key = "drift.saved_connections"
    private let neonKeyKey = "drift.neon_api_key"
    private let neonKeysKey = "drift.neon_api_keys"
    private let llmKeyKey = "drift.llm_api_key"

    func loadConnections() -> [SavedConnection] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SavedConnection].self, from: data)) ?? []
    }

    func saveConnections(_ connections: [SavedConnection]) {
        if let data = try? JSONEncoder().encode(connections) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func addConnection(_ connection: SavedConnection) {
        var connections = loadConnections()
        connections.append(connection)
        saveConnections(connections)
    }

    func removeConnection(id: UUID) {
        var connections = loadConnections()
        connections.removeAll { $0.id == id }
        saveConnections(connections)
    }

    func loadNeonAPIKeys() -> [NeonAPIKey] {
        if let data = UserDefaults.standard.data(forKey: neonKeysKey),
           let keys = try? JSONDecoder().decode([NeonAPIKey].self, from: data) {
            return keys
        }

        let legacyKey = UserDefaults.standard.string(forKey: neonKeyKey) ?? ""
        let trimmed = legacyKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let migrated = [NeonAPIKey(name: "Default", key: trimmed)]
        saveNeonAPIKeys(migrated)
        return migrated
    }

    func saveNeonAPIKeys(_ keys: [NeonAPIKey]) {
        if let data = try? JSONEncoder().encode(keys) {
            UserDefaults.standard.set(data, forKey: neonKeysKey)
        }
        UserDefaults.standard.set(keys.first?.key ?? "", forKey: neonKeyKey)
    }

    var neonAPIKeys: [NeonAPIKey] {
        get { loadNeonAPIKeys() }
        set { saveNeonAPIKeys(newValue) }
    }

    var neonAPIKey: String {
        get { loadNeonAPIKeys().first?.key ?? UserDefaults.standard.string(forKey: neonKeyKey) ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                saveNeonAPIKeys([])
            } else {
                saveNeonAPIKeys([NeonAPIKey(name: "Default", key: trimmed)])
            }
        }
    }

    var llmAPIKey: String {
        get { UserDefaults.standard.string(forKey: llmKeyKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: llmKeyKey) }
    }
}
