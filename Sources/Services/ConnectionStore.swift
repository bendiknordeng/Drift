import Foundation

final class ConnectionStore {
    private let key = "drift.saved_connections"
    private let neonKeyKey = "drift.neon_api_key"
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

    var neonAPIKey: String {
        get { UserDefaults.standard.string(forKey: neonKeyKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: neonKeyKey) }
    }

    var llmAPIKey: String {
        get { UserDefaults.standard.string(forKey: llmKeyKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: llmKeyKey) }
    }
}
