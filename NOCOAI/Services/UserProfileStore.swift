import Foundation

enum NocoPersonality: String, CaseIterable, Identifiable, Codable {
    case friendly
    case professional
    case balanced

    var id: String { rawValue }

    var label: String {
        switch self {
        case .friendly: return "Freundlich"
        case .professional: return "Professionell"
        case .balanced: return "Ausgewogen"
        }
    }

    var subtitle: String {
        switch self {
        case .friendly: return "Warm, locker"
        case .professional: return "Klar, sachlich"
        case .balanced: return "Menschlich, ausgewogen"
        }
    }
}

struct NocoUserProfile: Codable, Equatable {
    var userName: String
    var facts: [String]
    var personality: NocoPersonality
    var lastUpdated: String?

    static let empty = NocoUserProfile(userName: "", facts: [], personality: .balanced)

    enum CodingKeys: String, CodingKey {
        case userName, facts, personality, lastUpdated
    }

    init(userName: String, facts: [String], personality: NocoPersonality, lastUpdated: String? = nil) {
        self.userName = userName
        self.facts = facts
        self.personality = personality
        self.lastUpdated = lastUpdated
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userName = try c.decodeIfPresent(String.self, forKey: .userName) ?? ""
        facts = try c.decodeIfPresent([String].self, forKey: .facts) ?? []
        personality = try c.decodeIfPresent(NocoPersonality.self, forKey: .personality) ?? .balanced
        lastUpdated = try c.decodeIfPresent(String.self, forKey: .lastUpdated)
    }
}

@MainActor
final class UserProfileStore: ObservableObject {
    @Published var profile: NocoUserProfile = .empty
    @Published var draftFact = ""
    @Published var isSyncing = false
    @Published var lastError: String?

    private let localKey = "nocoai.userProfile"
    private weak var api: CompanionAPI?

    init() {
        loadLocal()
    }

    func bind(api: CompanionAPI?) {
        self.api = api
    }

    func loadLocal() {
        guard let data = UserDefaults.standard.data(forKey: localKey),
              let decoded = try? JSONDecoder().decode(NocoUserProfile.self, from: data) else {
            return
        }
        profile = decoded
    }

    private func persistLocal() {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: localKey)
        }
    }

    func setName(_ name: String) {
        profile.userName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        persistLocal()
        Task { await pushRemote() }
    }

    func setPersonality(_ p: NocoPersonality) {
        profile.personality = p
        persistLocal()
        Task { await pushRemote() }
    }

    func addFact(_ raw: String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 4 else { return }
        if !profile.facts.contains(t) {
            profile.facts.append(t)
            if profile.facts.count > 20 {
                profile.facts = Array(profile.facts.suffix(20))
            }
        }
        draftFact = ""
        persistLocal()
        Task { await pushRemote() }
    }

    func removeFact(_ fact: String) {
        profile.facts.removeAll { $0 == fact }
        persistLocal()
        Task { await pushRemote() }
    }

    func pullRemote() async {
        guard let api else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let remote = try await api.fetchProfile()
            profile = remote
            persistLocal()
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func pushRemote() async {
        guard let api else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let saved = try await api.saveProfile(profile)
            profile = saved
            persistLocal()
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
