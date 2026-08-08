import Foundation
import os.log

/// Internal Voice AI session diagnostics (Console / Instruments only — never shown in UI).
enum VoiceDebugLog {
    private static let logger = Logger(subsystem: "de.noco.nocoai", category: "VoiceAI")

    static func event(_ name: String, _ detail: String = "") {
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
}
