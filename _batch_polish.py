# -*- coding: utf-8 -*-
"""Batch polish: branding, speak, vision, chat limit, studio lag, image prompt."""
from pathlib import Path
import re

IOS = Path(r"C:\Users\noah_\Desktop\IOS NOCO AI X APP\github-repo-clean")
NOCO = IOS / "NOCOAI"
WIN = Path(r"C:\Users\noah_\NEW PROJECCCCCCCCCCCCCCT")


def write(p: Path, t: str):
    p.write_text(t, encoding="utf-8")
    print("wrote", p.relative_to(IOS) if str(p).startswith(str(IOS)) else p.name)


def branding():
    replacements = [
        ("Intelligence Sync", "NOCO Sync"),
        ("wie Apple Intelligence", "flüssig und klar"),
        ("weich wie Apple Intelligence.", "flüssig vom PC."),
        ("(wie Siri). ", ""),
        ("Apple Intelligence feel", "NOCO feel"),
        ("Apple Intelligence motion kit", "NOCO motion kit"),
        ("Apple Intelligence accent", "NOCO accent"),
        ("Visual Intelligence hub", "Studio hub"),
    ]
    for path in NOCO.rglob("*.swift"):
        t = path.read_text(encoding="utf-8")
        orig = t
        for a, b in replacements:
            t = t.replace(a, b)
        if t != orig:
            write(path, t)


def speak_audio_and_end():
    p = NOCO / "Services" / "VoiceService.swift"
    t = p.read_text(encoding="utf-8")
    t = t.replace("private let ttsGain: Float = 8.5", "private let ttsGain: Float = 4.0")
    t = t.replace("ttsEngine.mainMixerNode.outputVolume = 1.8", "ttsEngine.mainMixerNode.outputVolume = 1.15")
    t = t.replace("samples[i] = tanh(boosted * 1.05)", "samples[i] = tanh(boosted * 0.72)")
    # Faster speech rate in amplified + fallback
    t = t.replace(
        "utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.94",
        "utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.08",
    )
    write(p, t)

    p = NOCO / "Services" / "SpeakSessionController.swift"
    t = p.read_text(encoding="utf-8")
    # End-command detection + haptics on start/stop
    if "isEndSpeakCommand" not in t:
        t = t.replace(
            "        voice.onAutoUtterance = { [weak self] text in\n            Task { await self?.handleUtterance(text) }\n        }",
            "        voice.onAutoUtterance = { [weak self] text in\n"
            "            Task { await self?.handleUtterance(text) }\n"
            "        }",
        )
        # inject helper + modify handleUtterance
        old = """    private func handleUtterance(_ text: String) async {
        guard isRunning, !isBusy, let connection else { return }
        guard !isMuted else { return }
        isBusy = true
        defer { isBusy = false }

        statusLine = \"Intelligence Sync…\"
""".replace("Intelligence Sync…", "NOCO Sync…")  # may already be renamed
        # find actual
        m = re.search(
            r"private func handleUtterance\(_ text: String\) async \{[\s\S]*?guard !isMuted else \{ return \}\n",
            t,
        )
        if not m:
            raise SystemExit("handleUtterance not found")
        insert = """private func handleUtterance(_ text: String) async {
        guard isRunning, !isBusy, let connection else { return }
        guard !isMuted else { return }

        // Voice command: end speak without sending to the PC
        if Self.isEndSpeakCommand(text) {
            statusLine = "Sprachmodus beendet"
            HapticService.success()
            stop()
            showSpeakUI = false
            return
        }

        isBusy = true
        defer { isBusy = false }
"""
        t = t[: m.start()] + insert + t[m.end() :]
        helper = """
    private static func isEndSpeakCommand(_ text: String) -> Bool {
        let raw = text.lowercased()
        let cleaned = raw
            .replacingOccurrences(of: #"[^a-zäöüß\\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let phrases = [
            "sprachmodus beenden", "beende sprachmodus", "beenden sprachmodus",
            "ende sprachmodus", "stopp sprachmodus", "stop sprachmodus",
            "end language mode", "end speak", "stop speak", "speak beenden",
            "sprachmodus stoppen", "beende speak", "stopp speak"
        ]
        return phrases.contains(where: { cleaned == $0 || cleaned.contains($0) })
    }
"""
        if "isEndSpeakCommand" not in t:
            # before last closing of class
            idx = t.rfind("\n}")
            t = t[:idx] + helper + t[idx:]
        print("ok end speak command")

    # Haptics on start/stop
    if "HapticService.success()" not in t.split("func start()")[1][:800]:
        t = t.replace(
            "            try voice.startListening(autoEnd: true)\n",
            "            try voice.startListening(autoEnd: true)\n"
            "            HapticService.success()\n",
            1,
        )
    if "func stop()" in t and "HapticService.soft()" not in t[t.find("func stop()"): t.find("func stop()") + 400]:
        t = t.replace(
            "    func stop() {\n        resumeTask?.cancel()\n",
            "    func stop() {\n        HapticService.soft()\n        resumeTask?.cancel()\n",
            1,
        )
    # statusLine rename leftover
    t = t.replace("Intelligence Sync…", "NOCO Sync…")
    write(p, t)

    # Shortcut: don't force Speak UI sheet; Live Activity is enough (app still opens briefly — iOS limit)
    p = NOCO / "Services" / "SpeakAppIntents.swift"
    t = p.read_text(encoding="utf-8")
    t = t.replace(
        "Startet den Sprachmodus (wie Siri). Die App öffnet sich und hört sofort zu.",
        "Startet den Sprachmodus. Live Activity + Mikrofon — du kannst in anderen Apps bleiben.",
    )
    t = t.replace(
        "Startet den Sprachmodus. Die App öffnet sich und hört sofort zu.",
        "Startet den Sprachmodus. Live Activity + Mikrofon — du kannst in anderen Apps bleiben.",
    )
    # Keep openAppWhenRun true — required for mic on cold start; we avoid showing Speak sheet
    write(p, t)

    p = NOCO / "Services" / "ConnectionStore.swift"
    t = p.read_text(encoding="utf-8")
    # launch without forcing full Speak UI (Live Activity handles presence)
    t = t.replace(
        """    func launchSpeakFromShortcut() {
        SpeakLaunchBridge.pendingStart = true
        speak.openUI()
        Task { @MainActor in
            // Wait until paired + online (cold launch needs a few ticks)
            for _ in 0..<40 {
                if isPaired && isOnline { break }
                try? await Task.sleep(nanoseconds: 250_000_000)
                await refreshStatus(showLoading: false)
            }
            guard SpeakLaunchBridge.pendingStart else { return }
            speak.openUI()
            if isOnline {
                if !speak.isRunning {
                    speak.start()
                }
                SpeakLaunchBridge.clearPending()
            } else {
                speak.statusLine = \"PC offline — Companion starten, dann nochmal Shortcut\"
            }
        }
    }""",
        """    func launchSpeakFromShortcut() {
        SpeakLaunchBridge.pendingStart = true
        // Don't present Speak sheet — Live Activity + audio keep session usable in background
        Task { @MainActor in
            for _ in 0..<40 {
                if isPaired && isOnline { break }
                try? await Task.sleep(nanoseconds: 250_000_000)
                await refreshStatus(showLoading: false)
            }
            guard SpeakLaunchBridge.pendingStart else { return }
            if isOnline {
                if !speak.isRunning {
                    speak.start()
                }
                SpeakLaunchBridge.clearPending()
                HapticService.success()
            } else {
                speak.openUI()
                speak.statusLine = \"PC offline — Companion starten, dann nochmal Shortcut\"
            }
        }
    }""",
    )
    write(p, t)


def fix_vision():
    p = NOCO / "Store" / "ChatStore.swift"
    t = p.read_text(encoding="utf-8")
    old = """            if let assistant = result.asAssistantMessage() {
                messages.append(mapMessage(assistant))
                HapticService.messageReceived()
            }

            await resolveConversationId(activeConversationId, preferLatest: isStartingNewChat)
            await syncFromServer()
            HapticService.success()"""
    new = """            var keptAssistant: ChatMessage?
            if let assistant = result.asAssistantMessage() {
                let mapped = mapMessage(assistant)
                messages.append(mapped)
                keptAssistant = mapped
                HapticService.messageReceived()
            } else if let text = result.replyText, !text.isEmpty {
                let mapped = ChatMessage(role: .assistant, text: text)
                messages.append(mapped)
                keptAssistant = mapped
                HapticService.messageReceived()
            }

            await resolveConversationId(activeConversationId, preferLatest: isStartingNewChat)
            // Soft sync — never wipe a fresh vision reply if the server lags
            await softSyncPreservingVision(localAssistant: keptAssistant)
            HapticService.success()"""
    if "softSyncPreservingVision" not in t:
        t = t.replace(old, new, 1)
        helper = """
    private func softSyncPreservingVision(localAssistant: ChatMessage?) async {
        let snapshotUser = messages.filter { $0.localImageData != nil }
        let snapshotAssistant = localAssistant
        await pollSync()
        if let id = activeConversationId {
            try? await Task.sleep(nanoseconds: 450_000_000)
            await loadMessages(for: id)
        }
        await loadConversations()

        // If server reload dropped the vision answer, put it back
        if let snap = snapshotAssistant {
            let hasText = messages.contains {
                $0.role == .assistant && !$0.text.isEmpty &&
                ($0.text == snap.text || $0.serverId == snap.serverId)
            }
            if !hasText {
                messages.append(snap)
            }
        }
        // Restore local image thumbnails on matching user bubbles
        for local in snapshotUser {
            if let idx = messages.firstIndex(where: {
                $0.role == .user && $0.localImageData == nil &&
                ($0.text == local.text || $0.id == local.id)
            }) {
                messages[idx].localImageData = local.localImageData
            }
        }
    }
"""
        idx = t.rfind("\n}")
        t = t[:idx] + helper + t[idx:]
        write(p, t)
    else:
        print("skip vision")


def chat_limit_and_ui():
    # Add published banner + compact method to ChatStore
    p = NOCO / "Store" / "ChatStore.swift"
    t = p.read_text(encoding="utf-8")
    if "chatLimitReached" not in t:
        t = t.replace(
            "    @Published var peerTypingDraft: String?\n",
            "    @Published var peerTypingDraft: String?\n"
            "    @Published var chatLimitReached = false\n"
            "    @Published var isCompacting = false\n"
            "    private let softMessageLimit = 36\n"
            "    private let keepAfterCompact = 30\n",
            1,
        )
        # After successful send, check limit
        t = t.replace(
            "            await resolveConversationId(conversationId, preferLatest: isStartingNewChat)\n"
            "            await syncFromServer()\n"
            "            HapticService.success()\n"
            "        } catch is CancellationError {",
            "            await resolveConversationId(conversationId, preferLatest: isStartingNewChat)\n"
            "            await syncFromServer()\n"
            "            evaluateChatLimit()\n"
            "            HapticService.success()\n"
            "        } catch is CancellationError {",
            1,
        )
        helpers = """
    private func evaluateChatLimit() {
        chatLimitReached = messages.count >= softMessageLimit
    }

    /// Summarize long chat, keep last N messages, drop the rest (new compact thread on PC).
    func compactChatBecauseLimit() async {
        guard let api, let oldId = activeConversationId, !isCompacting else { return }
        isCompacting = true
        chatLimitReached = false
        defer { isCompacting = false }

        let transcript = messages.suffix(80).map { msg in
            let who = msg.role == .user ? "Nutzer" : "NOCO"
            return "\\(who): \\(msg.text.prefix(500))"
        }.joined(separator: "\\n")

        let prompt = \"\"\"
        Der Chat ist zu lang. Erstelle eine knappe Zusammenfassung auf Deutsch (8–12 Sätze)
        der wichtigsten Fakten, Entscheidungen und offenen Punkte. Keine Floskeln.
        Danach antwortet das System nur noch mit dieser Zusammenfassung.

        Chat:
        \\(transcript.prefix(6000))
        \"\"\"

        statusLinePlaceholder()
        let summary = await sendAndReturnReply(prompt, modeOverride: .flash) ?? ""
        let cleanSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)

        // Keep last messages for local continuity, then open a fresh conversation seeded with summary
        let tail = Array(messages.suffix(keepAfterCompact))
        do {
            let created = try await api.createConversation(title: "Fortsetzung (Zusammenfassung)")
            if let newId = created.id ?? created.conversationId {
                activeConversationId = newId
                persistActiveConversation()
                messages = [
                    ChatMessage(
                        role: .assistant,
                        text: cleanSummary.isEmpty
                            ? "Chat verdichtet — wir machen hier weiter."
                            : "Zusammenfassung bisher:\\n\\n\\(cleanSummary)"
                    )
                ]
                // Optionally nudge PC with summary as first user note
                if !cleanSummary.isEmpty {
                    _ = await sendAndReturnReply(
                        "[Kontext aus vorherigem Chat]\\n\\(cleanSummary)\\n\\nBitte an diesen Kontext anknüpfen.",
                        modeOverride: .flash
                    )
                }
                // Delete old oversized thread on PC
                deletedIds.insert(oldId)
                persistDeletedIds()
                try? await api.deleteConversation(id: oldId)
                conversations.removeAll { $0.id == oldId }
                await loadConversations()
                chatLimitReached = false
                HapticService.success()
                return
            }
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            // Fallback: trim locally
            messages = Array(tail.suffix(keepAfterCompact))
            if !cleanSummary.isEmpty {
                messages.insert(
                    ChatMessage(role: .assistant, text: "Zusammenfassung:\\n\\(cleanSummary)"),
                    at: 0
                )
            }
            HapticService.error()
        }
        _ = tail
    }

    private func statusLinePlaceholder() {}
"""
        # CreateConversationResponse fields - check
        idx = t.rfind("\n}")
        t = t[:idx] + helpers + t[idx:]
        # Also evaluate after loadMessages
        t = t.replace(
            "            } else {\n                messages = serverMessages\n            }",
            "            } else {\n                messages = serverMessages\n            }\n"
            "            evaluateChatLimit()",
            1,
        )
        write(p, t)
    else:
        print("skip chat limit store")


def check_create_response():
    p = NOCO / "Models" / "V2Models.swift"
    t = p.read_text(encoding="utf-8")
    if "struct CreateConversationResponse" in t:
        print(t[t.find("struct CreateConversationResponse"): t.find("struct CreateConversationResponse") + 250])


def image_prompt_local_state():
    p = NOCO / "Views" / "Images" / "ImagesHubView.swift"
    t = p.read_text(encoding="utf-8")
    if "@State private var draftPrompt" in t:
        print("skip draft prompt")
        return
    t = t.replace(
        "    @FocusState private var promptFocused: Bool\n",
        "    @FocusState private var promptFocused: Bool\n"
        "    @State private var draftPrompt = \"\"\n",
        1,
    )
    t = t.replace(
        """                TextField(\"Beschreibe dein Bild…\", text: Binding(
                    get: { connection.images.prompt },
                    set: { connection.images.prompt = $0 }
                ), axis: .vertical)
                .lineLimit(3...6)
                .focused($promptFocused)
                .submitLabel(.done)
                .onSubmit { promptFocused = false }
                .onChange(of: connection.images.prompt) { _, newValue in
                    if newValue.contains(where: { $0 == \"\\n\" || $0 == \"\\r\" }) {
                        connection.images.prompt = newValue
                            .replacingOccurrences(of: \"\\r\", with: \"\")
                            .replacingOccurrences(of: \"\\n\", with: \"\")
                        promptFocused = false
                    }
                }
                .disabled(connection.images.isGenerating)""",
        """                TextField(\"Beschreibe dein Bild…\", text: $draftPrompt, axis: .vertical)
                .lineLimit(3...6)
                .focused($promptFocused)
                .submitLabel(.done)
                .onSubmit { promptFocused = false }
                .disabled(connection.images.isGenerating)""",
        1,
    )
    t = t.replace(
        "                                    connection.images.prompt = tip\n",
        "                                    draftPrompt = tip\n"
        "                                    connection.images.prompt = tip\n",
    )
    t = t.replace(
        """                    Button {
                        promptFocused = false
                        reveal = false
                        HapticService.medium()
                        connection.images.startGenerate()
                    } label: {""",
        """                    Button {
                        promptFocused = false
                        connection.images.prompt = draftPrompt
                        reveal = false
                        HapticService.medium()
                        connection.images.startGenerate()
                    } label: {""",
        1,
    )
    t = t.replace(
        ".disabled(connection.images.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !connection.isOnline)\n"
        "                    .opacity(connection.images.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !connection.isOnline ? 0.5 : 1)",
        ".disabled(draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !connection.isOnline)\n"
        "                    .opacity(draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !connection.isOnline ? 0.5 : 1)",
        1,
    )
    # onAppear sync
    if ".task {" in t and "draftPrompt =" not in t.split(".task {")[1][:400]:
        t = t.replace(
            "            .task {\n                await connection.refreshGallery()\n",
            "            .task {\n                draftPrompt = connection.images.prompt\n"
            "                await connection.refreshGallery()\n",
            1,
        )
    write(p, t)


def studio_lag():
    p = NOCO / "Views" / "More" / "MoreView.swift"
    t = p.read_text(encoding="utf-8")
    t = t.replace("FloatingIntelligenceDots(count: 12)", "FloatingIntelligenceDots(count: 5)")
    t = t.replace(
        """            .overlay {
                FloatingIntelligenceDots(count: 5)
                    .opacity(0.35)
                    .allowsHitTesting(false)
            }
            .overlay {
                IntelligenceBreathingAura()
                    .opacity(0.4)
                    .allowsHitTesting(false)
            }""",
        """            .overlay {
                FloatingIntelligenceDots(count: 5)
                    .opacity(0.22)
                    .allowsHitTesting(false)
            }""",
    )
    t = t.replace('Text("NOCO AI Companion v3.5")', 'Text("NOCO AI Companion v4.6")')
    t = t.replace('title: "Intelligence Sync"', 'title: "NOCO Sync"')
    t = t.replace('title: "NOCO Sync"', 'title: "NOCO Sync"')  # noop if already
    write(p, t)


def chat_hub_banner():
    p = NOCO / "Views" / "Chat" / "ChatHubView.swift"
    t = p.read_text(encoding="utf-8")
    if "chatLimitReached" in t:
        print("skip chat banner")
        return
    needle = """                if connection.chat.peerTyping {
                    PeerTypingBanner(draft: connection.chat.peerTypingDraft)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                ChatInputBar("""
    insert = """                if connection.chat.peerTyping {
                    PeerTypingBanner(draft: connection.chat.peerTypingDraft)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if connection.chat.chatLimitReached || connection.chat.isCompacting {
                    ChatLimitBanner(
                        isCompacting: connection.chat.isCompacting,
                        onCompact: {
                            Task { await connection.chat.compactChatBecauseLimit() }
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                ChatInputBar("""
    if needle not in t:
        raise SystemExit("chat hub needle missing")
    t = t.replace(needle, insert, 1)
    # append ChatLimitBanner struct at end of file
    t += """

private struct ChatLimitBanner: View {
    var isCompacting: Bool
    var onCompact: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.badge.minus")
                .foregroundStyle(NOCOAITheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(isCompacting ? "Chat wird verdichtet…" : "Chat-Limit erreicht")
                    .font(.subheadline.weight(.semibold))
                Text(isCompacting
                     ? "Zusammenfassung wird erstellt."
                     : "Über ~35 Nachrichten — Zusammenfassung hält den Kontext schlank.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if !isCompacting {
                Button("Verdichten", action: onCompact)
                    .font(.caption.weight(.bold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                ProgressView()
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(NOCOAITheme.glowPrimary.opacity(0.35), lineWidth: 1)
        )
    }
}
"""
    # branding in empty state
    t = t.replace("weich wie Apple Intelligence.", "flüssig vom PC.")
    t = t.replace("Dein PC rechnet — Antworten streamen\nflüssig und klar.", "Dein PC rechnet — Antworten streamen\nflüssig vom PC.")
    write(p, t)


def bump():
    p = IOS / "NOCOAI.xcodeproj" / "project.pbxproj"
    t = p.read_text(encoding="utf-8")
    t = t.replace("CURRENT_PROJECT_VERSION = 29;", "CURRENT_PROJECT_VERSION = 30;")
    t = t.replace("MARKETING_VERSION = 4.5;", "MARKETING_VERSION = 4.6;")
    write(p, t)


def fix_create_conversation_fields():
    # Ensure CreateConversationResponse has id
    p = NOCO / "Models" / "V2Models.swift"
    t = p.read_text(encoding="utf-8")
    print("--- CreateConversation ---")
    i = t.find("CreateConversation")
    print(t[i:i+400] if i >= 0 else "NOT FOUND")


if __name__ == "__main__":
    branding()
    speak_audio_and_end()
    fix_vision()
    check_create_response()
    fix_create_conversation_fields()
    chat_limit_and_ui()
    image_prompt_local_state()
    studio_lag()
    chat_hub_banner()
    bump()
    print("BATCH DONE")
