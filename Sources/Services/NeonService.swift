import Foundation

final class NeonService {
    private let baseURL = "https://console.neon.tech/api/v2"
    var apiKey: String = ""

    var isConfigured: Bool { !apiKey.isEmpty }

    func fetchOrganizations() async throws -> [NeonOrganization] {
        let data = try await request(path: "/users/me/organizations")
        let wrapper = try JSONDecoder().decode(OrganizationsResponse.self, from: data)
        return wrapper.organizations
    }

    func fetchProjects(orgId: String?) async throws -> [NeonProject] {
        var path = "/projects"
        if let orgId {
            path += "?org_id=\(orgId)"
        }
        let data = try await request(path: path)
        let wrapper = try JSONDecoder().decode(ProjectsResponse.self, from: data)
        return wrapper.projects
    }

    func fetchBranches(projectId: String) async throws -> [NeonBranch] {
        let data = try await request(path: "/projects/\(projectId)/branches")
        let wrapper = try JSONDecoder().decode(BranchesResponse.self, from: data)
        return wrapper.branches
    }

    func fetchDatabases(projectId: String, branchId: String) async throws -> [NeonDatabase] {
        let data = try await request(path: "/projects/\(projectId)/branches/\(branchId)/databases")
        let wrapper = try JSONDecoder().decode(DatabasesResponse.self, from: data)
        return wrapper.databases
    }

    func fetchRoles(projectId: String, branchId: String) async throws -> [NeonRole] {
        let data = try await request(path: "/projects/\(projectId)/branches/\(branchId)/roles")
        let wrapper = try JSONDecoder().decode(RolesResponse.self, from: data)
        return wrapper.roles
    }

    func fetchConnectionURI(projectId: String, branchId: String, database: String, role: String) async throws -> String {
        let encodedDB = database.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? database
        let encodedRole = role.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? role
        let path = "/projects/\(projectId)/connection_uri?branch_id=\(branchId)&database_name=\(encodedDB)&role_name=\(encodedRole)"
        let data = try await request(path: path)
        let wrapper = try JSONDecoder().decode(NeonConnectionURI.self, from: data)
        return wrapper.uri
    }

    private func request(path: String) async throws -> Data {
        guard isConfigured else { throw DriftError.neonAPIError("API key not configured") }

        var req = URLRequest(url: URL(string: baseURL + path)!)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw DriftError.neonAPIError("Invalid response")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DriftError.neonAPIError("HTTP \(http.statusCode): \(body)")
        }
        return data
    }

    // MARK: - Response wrappers

    private struct OrganizationsResponse: Codable { let organizations: [NeonOrganization] }
    private struct ProjectsResponse: Codable { let projects: [NeonProject] }
    private struct BranchesResponse: Codable { let branches: [NeonBranch] }
    private struct DatabasesResponse: Codable { let databases: [NeonDatabase] }
    private struct RolesResponse: Codable { let roles: [NeonRole] }
}
