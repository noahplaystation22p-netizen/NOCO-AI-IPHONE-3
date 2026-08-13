import Foundation

/// Compact models for Companion `/api/v1/running/*` (NOCO RUNNING plugin).

struct RunningStatusResponse: Decodable {
    let success: Bool?
    let plugin: String?
    let version: String?
    let supported: Bool?
    let server: RunningServerInfo?
    let ollama: Bool?
    let runs: Int?
    let distanceKm: Double?
    let lastRunAt: String?
    let lastAnalysisAt: String?
}

struct RunningServerInfo: Decodable {
    let online: Bool?
    let host: String?
    let port: Int?
    let devices: Int?
}

struct RunningRun: Decodable, Identifiable {
    let id: String
    let clientRunId: String?
    let date: String?
    let startTime: String?
    let title: String?
    let routeName: String?
    let distanceKm: Double?
    let durationSec: Double?
    let avgPaceSecPerKm: Double?
    let source: String?
}

struct RunningDataResponse: Decodable {
    let success: Bool?
    let runs: [RunningRun]?
}

struct RunningStats: Decodable {
    let runCount: Int?
    let totalDistanceKm: Double?
    let totalDurationSec: Double?
    let avgPaceSecPerKm: Double?
    let avgDistanceKm: Double?
    let thisWeekDistanceKm: Double?
    let thisMonthDistanceKm: Double?
    let bestPaceSecPerKm: Double?
    let longestRunKm: Double?
    let mostFrequentRoute: String?
    let lastRunAt: String?
}

struct RunningWeeklyPoint: Decodable, Identifiable {
    var id: String { period ?? UUID().uuidString }
    let period: String?
    let distanceKm: Double?
    let count: Int?
}

struct RunningStatsResponse: Decodable {
    let success: Bool?
    let stats: RunningStats?
    let series: RunningSeries?
}

struct RunningSeries: Decodable {
    let weeklyDistance: [RunningWeeklyPoint]?
}

struct RunningActivityResponse: Decodable {
    let success: Bool?
    let lines: [String]?
}

struct RunningAskResponse: Decodable {
    let success: Bool?
    let conversationId: String?
    let answer: String?
    let referencedRunIds: [String]?
    let model: String?
}

struct RunningAnalysis: Decodable {
    let id: String?
    let createdAt: String?
    let summary: String?
    let insights: [String]?
    let recommendations: [String]?
    let confidence: Double?
    let model: String?
}

struct RunningAnalyzeResponse: Decodable {
    let success: Bool?
    let analysis: RunningAnalysis?
}

struct RunningImportResponse: Decodable {
    let success: Bool?
    let imported: Int?
    let updated: Int?
    let skipped: Int?
    let rejected: Int?
}

enum RunningFormat {
    static func pace(_ sec: Double?) -> String {
        guard let sec, sec > 0 else { return "—" }
        let m = Int(sec) / 60
        let s = Int(sec.rounded()) % 60
        return "\(m):\(String(format: "%02d", s))"
    }

    static func duration(_ sec: Double?) -> String {
        guard let sec, sec >= 0 else { return "—" }
        let total = Int(sec.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", s))" }
        return "\(m):\(String(format: "%02d", s))"
    }

    static func km(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f km", value)
    }

    static func shortDate(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "—" }
        let prefix = String(iso.prefix(10))
        let parts = prefix.split(separator: "-")
        guard parts.count == 3 else { return prefix }
        return "\(parts[2]).\(parts[1]).\(parts[0])"
    }
}
