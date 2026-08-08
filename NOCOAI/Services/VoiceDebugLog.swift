import Foundation
import os.log

/// Internal Voice AI session diagnostics (Console / Instruments only — never shown in UI).
enum VoiceDebugLog {
    private static let logger = Logger(subsystem: "de.noco.nocoai", category: "VoiceAI")
    private static let storageKey = "nocoai.voice.debugLog.lines"
    private static let maxStoredLines = 450

    static func event(_ name: String, _ detail: String = "") {
        appendStoredLine(name: name, detail: detail)
        #if DEBUG
        if detail.isEmpty {
            logger.debug("VOICE \(name, privacy: .public)")
        } else {
            logger.debug("VOICE \(name, privacy: .public) | \(detail, privacy: .public)")
        }
        #else
        // Release: still log at info for field diagnosis via Console.app when connected.
        if detail.isEmpty {
            logger.info("VOICE \(name, privacy: .public)")
        } else {
            logger.info("VOICE \(name, privacy: .public) | \(detail, privacy: .public)")
        }
        #endif
    }

    static func exportText() -> String {
        let lines = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        guard !lines.isEmpty else { return "Keine Voice-Logs vorhanden." }
        return lines.joined(separator: "\n")
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private static func appendStoredLine(name: String, detail: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = detail.isEmpty
            ? "\(timestamp) VOICE \(name)"
            : "\(timestamp) VOICE \(name) | \(detail)"
        var lines = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        lines.append(line)
        if lines.count > maxStoredLines {
            lines.removeFirst(lines.count - maxStoredLines)
        }
        UserDefaults.standard.set(lines, forKey: storageKey)
    }
}
