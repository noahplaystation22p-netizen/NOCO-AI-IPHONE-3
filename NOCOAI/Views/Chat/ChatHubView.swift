import SwiftUI
import UIKit

struct ChatHubView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme
    @State private var input = ""
    @State private var showConversations = false
    @State private var showWritingTools = false
    @State private var edgeHint: CGFloat = 0
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let error = connection.chat.lastError {
                    Button {
                        connection.chat.lastError = nil
                    } label: {
                        HStack(spacing: 8) {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "xmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(NOCOAITheme.danger.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        if connection.chat.messages.isEmpty {
                            emptyState
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(Array(connection.chat.messages.enumerated()), id: \.element.id) { index, message in
                                    ChatBubble(message: message) { action in
                                        Task {
                                            if action == .shorter {
                                                let level = connection.chat.nextShortenLevel(for: message.id)
                                                await connection.chat.send(
                                                    action.prompt(for: message.text, shortenLevel: level)
                                                )
                                            } else {
                                                await connection.chat.send(action.prompt(for: message.text))
                                            }
                                            if action == .asImagePrompt {
                                                connection.handoffToImages(prompt: message.text)
                                            }
                                        }
                                    }
                                    .intelligenceMessageArrive()
                                    .id(message.id)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .animation(.spring(response: 0.38, dampingFraction: 0.84), value: connection.chat.messages.count)
                        }
                    }
                    .onTapGesture { inputFocused = false }
                    .onChange(of: connection.chat.messages.count) { _, _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: connection.chat.messages.last?.text) { _, _ in
                        scrollToBottom(proxy)
                    }
                }

                if connection.chat.peerTyping {
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

                if let pending = connection.chat.pendingAgentConfirm {
                    AgentInlineConfirmBar(
                        title: pending.title,
                        detail: pending.detail,
                        onAllow: {
                            Task { await connection.chat.respondAgentConfirm(allow: true) }
                        },
                        onDeny: {
                            Task { await connection.chat.respondAgentConfirm(allow: false) }
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                ChatInputBar(
                    text: $input,
                    focused: $inputFocused,
                    onSend: {
                        let text = input
                        input = ""
                        Task { await connection.chat.send(text) }
                    },
                    onVoice: { connection.speak.openUI() },
                    onWritingTools: { showWritingTools = true }
                )
                .onChange(of: input) { _, newValue in
                    connection.chat.noteDraftChanged(newValue)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: connection.chat.peerTyping)
            .nocoBackground()
            .navigationTitle(titleText)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        HapticService.open()
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                            showConversations = true
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .symbolEffect(.bounce, value: showConversations)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        if connection.chat.isSyncActive {
                            SyncBadge(active: true)
                        }
                        StatusBadge(
                            online: connection.isOnline,
                            label: connection.isReconnecting
                                ? "Verbindung…"
                                : (connection.isOnline ? "Online" : "Offline"),
                            detail: connection.isReconnecting
                                ? "wird wiederhergestellt"
                                : (connection.isOnline ? connection.onlineBadgeDetail : nil)
                        )
                    }
                }
            }
            .overlay(alignment: .leading) {
                // Left-edge swipe → conversation list
                Color.clear
                    .frame(width: 22)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 16, coordinateSpace: .local)
                            .onChanged { value in
                                if value.translation.width > 28, edgeHint < 1 {
                                    edgeHint = min(1, value.translation.width / 120)
                                }
                            }
                            .onEnded { value in
                                let shouldOpen = value.translation.width > 70
                                    && abs(value.translation.height) < 80
                                edgeHint = 0
                                if shouldOpen {
                                    HapticService.open()
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                                        showConversations = true
                                    }
                                }
                            }
                    )
                    .allowsHitTesting(true)
            }
            .overlay(alignment: .leading) {
                if edgeHint > 0.05 {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    NOCOAITheme.glowPrimary.opacity(0.35 * edgeHint),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 56 * edgeHint)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .sheet(isPresented: $showConversations) {
                ConversationListView()
                    .environmentObject(connection)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showWritingTools) {
                WritingToolsSheet(sourceText: input.isEmpty ? (connection.chat.messages.last(where: { $0.role == .assistant })?.text ?? "") : input) { tool in
                    let source = input.isEmpty
                        ? (connection.chat.messages.last(where: { $0.role == .user || $0.role == .assistant })?.text ?? "")
                        : input
                    guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    input = ""
                    Task { await connection.chat.send(tool.prompt(for: source)) }
                }
            }
            .onAppear { HapticService.prepare() }
            .onChange(of: connection.pendingChatDraft) { _, draft in
                guard let draft, !draft.isEmpty else { return }
                input = draft
                connection.pendingChatDraft = nil
                inputFocused = true
                HapticService.soft()
            }
            .intelligenceSelectionFeedback(connection.chat.mode)
            .task {
                if let draft = connection.pendingChatDraft, !draft.isEmpty {
                    input = draft
                    connection.pendingChatDraft = nil
                    inputFocused = true
                }
                connection.chat.restoreSession()
                await connection.chat.loadConversations()
                connection.chat.ensureActiveIsNotKeyboard()
                if let id = connection.chat.activeConversationId {
                    await connection.chat.loadMessages(for: id)
                } else if let first = connection.chat.filteredConversations.first {
                    await connection.chat.selectConversation(first.id)
                }
            }
        }
    }

    private var titleText: String {
        connection.chat.conversations.first(where: { $0.id == connection.chat.activeConversationId })?.title ?? "Chat"
    }

    private var emptyState: some View {
        ZStack {
            IntelligenceBreathingAura()
                .opacity(0.55)
                .allowsHitTesting(false)
            FloatingIntelligenceDots(count: 8)
                .opacity(0.22)
                .frame(height: 320)
            VStack(spacing: 16) {
                ZStack {
                    IntelligenceOrbitRings(size: 118)
                        .opacity(0.6)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    NOCOAITheme.glowPrimary.opacity(0.35),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 4,
                                endRadius: 56
                            )
                        )
                        .frame(width: 110, height: 110)
                        .blur(radius: 8)
                    Image(systemName: "sparkles")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(NOCOAITheme.accent)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                }
                .padding(.top, 40)

                Text("NOCO AI")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [NOCOAITheme.glowPrimary, NOCOAITheme.glowSecondary, NOCOAITheme.glowAccent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Text("Frag NOCO")
                    .font(.title3.weight(.semibold))

                Text(connection.isOnline
                    ? "Tippe unten — oder öffne + für Kamera, Agent und mehr."
                    : "Zuerst Companion verbinden.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(NOCOAITheme.secondaryText(for: scheme))
                    .padding(.horizontal, 32)

                IntelligenceWaveRibbon()
                    .frame(height: 24)
                    .padding(.horizontal, 36)
                    .opacity(0.75)

                HStack(spacing: 18) {
                    emptyHint(icon: "waveform.circle.fill", title: "Speak")
                    emptyHint(icon: "paintbrush.pointed.fill", title: "Bilder")
                    emptyHint(icon: "cpu.fill", title: "Agent")
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 24)
    }

    private func emptyHint(icon: String, title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(NOCOAITheme.accent)
                .symbolEffect(.pulse, options: .repeating.speed(0.4))
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: 72)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let last = connection.chat.messages.last {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

private struct PeerTypingBanner: View {
    var draft: String?
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [NOCOAITheme.glowPrimary, NOCOAITheme.glowSecondary],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 7, height: 7)
                        .scaleEffect(phase == i ? 1.35 : 0.8)
                        .opacity(phase == i ? 1 : 0.35)
                        .shadow(color: NOCOAITheme.glowPrimary.opacity(phase == i ? 0.7 : 0), radius: 5)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("PC tippt…")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NOCOAITheme.accent)
                if let draft, !draft.isEmpty {
                    Text(draft)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(NOCOAITheme.glowPrimary.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: NOCOAITheme.glowPrimary.opacity(0.2), radius: 10)
        )
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 280_000_000)
                phase = (phase + 1) % 3
            }
        }
    }
}

private struct ChatBubble: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme
    let message: ChatMessage
    var onReplyAction: ((ReplyAction) -> Void)?
    @State private var copiedFlash = false

    var body: some View {
        HStack(alignment: .bottom) {
            if message.role == .user { Spacer(minLength: 48) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                if let data = message.localImageData, let uiImage = UIImage(data: data) {
                    Button {
                        HapticService.soft()
                        if connection.speak.voice.isSpeakingNow {
                            connection.speak.voice.stopSpeaking(notifyFinished: true)
                        } else {
                            connection.openGalleryImage(url: message.imageURL, serverId: message.serverId)
                        }
                    } label: {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: NOCOAITheme.glowPrimary.opacity(0.25), radius: 12)
                    }
                    .buttonStyle(.plain)
                } else if let url = message.imageURL {
                    Button {
                        HapticService.soft()
                        if connection.speak.voice.isSpeakingNow {
                            connection.speak.voice.stopSpeaking(notifyFinished: true)
                        } else {
                            connection.openGalleryImage(url: url, serverId: message.serverId)
                        }
                    } label: {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFit().frame(maxHeight: 240).clipShape(RoundedRectangle(cornerRadius: 16))
                            case .failure:
                                Image(systemName: "photo").frame(height: 120)
                            default:
                                ProgressView().frame(height: 120)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                if !message.text.isEmpty || message.isStreaming {
                    if message.isStreaming && message.text.isEmpty {
                        IntelligenceThinkingStatus(
                            mode: statusMode(for: message),
                            phase: connection.chat.workPhase == .idle
                                ? .understanding
                                : connection.chat.workPhase,
                            isFile: lastUserLooksLikeFile,
                            statusOverride: connection.reconnectStatusLine ?? connection.chat.reconnectHint
                        )
                    } else {
                        bubbleText
                    }
                }

                if !message.isStreaming, !message.text.isEmpty {
                    if message.webUsed {
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                                .font(.caption2.weight(.bold))
                            Text("Web verwendet")
                                .font(.caption2.weight(.semibold))
                            if !message.webSourceTitles.isEmpty {
                                Text("· \(message.webSourceTitles.prefix(2).joined(separator: ", "))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .foregroundStyle(Color(red: 0.3, green: 0.55, blue: 0.95))
                        .padding(.top, 2)
                    }
                    MessageActionRow(
                        message: message,
                        copiedFlash: copiedFlash,
                        isSpeaking: connection.speak.voice.isSpeakingNow,
                        onCopy: { copyWholeMessage() },
                        onSpeak: {
                            HapticService.speakCue()
                            connection.speak.voice.toggleSpeak(message.text)
                        },
                        onShare: { shareMessage(message.text) },
                        onMore: { action in
                            handleMore(action, message: message, onReplyAction: onReplyAction)
                        }
                    )
                }
            }
            if message.role == .assistant { Spacer(minLength: 48) }
        }
    }

    private var lastUserLooksLikeFile: Bool {
        guard let text = connection.chat.messages.last(where: { $0.role == .user })?.text else { return false }
        return text.hasPrefix("Dokument „") || text.hasPrefix("Dokument \"")
    }

    private func statusMode(for message: ChatMessage) -> AIMode {
        let label = (message.modelLabel ?? "").lowercased()
        if label.contains("vision") { return .vision }
        if label.contains("bild") || label.contains("image") { return .image }
        if label.contains("agent") { return .agent }
        if label.contains("schreib") || label.contains("writing") { return .writing }
        if connection.chat.messages.last(where: { $0.role == .user })?.localImageData != nil,
           connection.chat.mode != .agent, connection.chat.mode != .image {
            return .vision
        }
        return connection.chat.mode
    }

    @ViewBuilder
    private var bubbleText: some View {
        Group {
            if message.isStreaming {
                HStack(alignment: .bottom, spacing: 6) {
                    Text(message.text)
                        .font(.body)
                        .foregroundStyle(message.role == .user ? .white : NOCOAITheme.primaryText(for: scheme))
                    StreamingGlowCursor()
                }
            } else {
                // Long-press selects words; system Copy = selection only.
                // Copy button below copies the whole message.
                SelectableMessageText(
                    text: message.text,
                    textColor: message.role == .user
                        ? .white
                        : UIColor(NOCOAITheme.primaryText(for: scheme))
                )
                .frame(maxWidth: UIScreen.main.bounds.width * 0.72, alignment: message.role == .user ? .trailing : .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(GlowBubbleBackground(isUser: message.role == .user, streaming: message.isStreaming))
        .intelligenceStreaming(message.isStreaming && message.role == .assistant)
        .animation(.easeOut(duration: 0.12), value: message.text)
        .contextMenu {
            Button {
                copyWholeMessage()
            } label: {
                Label("Alles kopieren", systemImage: "doc.on.doc")
            }
        }
    }

    private func copyWholeMessage() {
        MessageClipboard.copy(message.text)
        HapticService.success()
        withAnimation(.easeOut(duration: 0.2)) { copiedFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { copiedFlash = false }
        }
    }

    private func shareMessage(_ text: String) {
        let plain = MessageClipboard.plainText(from: text)
        guard !plain.isEmpty else { return }
        let av = UIActivityViewController(activityItems: [plain], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController ?? scene.windows.first?.rootViewController else { return }
        var presenter = root
        while let presented = presenter.presentedViewController { presenter = presented }
        presenter.present(av, animated: true)
        HapticService.soft()
    }

    private func handleMore(_ action: MessageMoreAction, message: ChatMessage, onReplyAction: ((ReplyAction) -> Void)?) {
        switch action {
        case .retryThink:
            Task {
                await connection.chat.send(
                    "Bitte generiere deine letzte Antwort erneut — gründlicher durchdacht, gleiche Absicht. Kein Meta-Kommentar.",
                    modeOverride: .think
                )
            }
        case .retryFlash:
            Task {
                await connection.chat.send(
                    "Bitte generiere deine letzte Antwort erneut — knapp und klar, gleiche Absicht. Kein Meta-Kommentar.",
                    modeOverride: .flash
                )
            }
        case .regenerate:
            Task {
                await connection.chat.send("Bitte generiere deine letzte Antwort erneut — klarer und besser, gleiche Absicht.")
            }
        case .showModel:
            let label = message.modelLabel ?? connection.chat.mode.modelHint
            HapticService.selection()
            connection.speak.statusLine = "Modell: \(label)"
        case .newChatFromHere:
            Task {
                _ = await connection.chat.newConversation()
                connection.pendingChatDraft = "Weiter zu:\n\n\(message.text.prefix(400))"
            }
        case .shorter:
            onReplyAction?(.shorter)
        case .longer:
            onReplyAction?(.longer)
        case .asList:
            onReplyAction?(.asList)
        case .asAgent:
            connection.handoffToAgent(goal: message.text)
        case .asImage:
            onReplyAction?(.asImagePrompt)
        }
    }
}

enum MessageMoreAction {
    case retryThink, retryFlash, regenerate, showModel, newChatFromHere, shorter, longer, asList, asAgent, asImage
}

private struct MessageActionRow: View {
    let message: ChatMessage
    var copiedFlash: Bool
    var isSpeaking: Bool = false
    var onCopy: () -> Void
    var onSpeak: () -> Void
    var onShare: () -> Void
    var onMore: (MessageMoreAction) -> Void

    var body: some View {
        HStack(spacing: 2) {
            iconButton(copiedFlash ? "checkmark" : "doc.on.doc", label: "Kopieren", action: onCopy)
            if message.role == .assistant {
                iconButton(
                    isSpeaking ? "stop.fill" : "speaker.wave.2.fill",
                    label: isSpeaking ? "Stoppen" : "Vorlesen",
                    action: onSpeak
                )
            }
            iconButton("square.and.arrow.up", label: "Teilen", action: onShare)
            Menu {
                if message.role == .assistant {
                    Button { onMore(.retryThink) } label: { Label("Retry (Think)", systemImage: "brain.head.profile") }
                    Button { onMore(.retryFlash) } label: { Label("Retry (Flash)", systemImage: "bolt.fill") }
                    Button { onMore(.shorter) } label: { Label("Kürzer", systemImage: "arrow.down.right.and.arrow.up.left") }
                    Button { onMore(.longer) } label: { Label("Ausführlicher", systemImage: "arrow.up.left.and.arrow.down.right") }
                    Divider()
                    Button { onMore(.asAgent) } label: { Label("An Agent", systemImage: "cpu.fill") }
                    Button { onMore(.asImage) } label: { Label("Als Bildidee", systemImage: "paintbrush.pointed") }
                } else {
                    Button { onMore(.asAgent) } label: { Label("An Agent", systemImage: "cpu.fill") }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel("Mehr")
        }
        .padding(.top, 2)
    }

    private func iconButton(_ system: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct ConversationListView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        HapticService.medium()
                        Task {
                            _ = await connection.chat.newConversation()
                            dismiss()
                        }
                    } label: {
                        Label("Neuer Chat", systemImage: "plus.bubble.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(NOCOAITheme.accent)
                    }
                }

                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(NOCOAITheme.accent)
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                        Text("Wische von links oder tippe ☰")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Unterhaltungen") {
                    ForEach(Array(connection.chat.filteredConversations.enumerated()), id: \.element.id) { index, convo in
                        Button {
                            HapticService.selection()
                            Task {
                                await connection.chat.selectConversation(convo.id)
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(NOCOAITheme.accent.opacity(0.14))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "bubble.left.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(NOCOAITheme.accent)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(convo.title).font(.headline)
                                    if let updated = convo.updatedAt {
                                        Text(updated).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                                if convo.id == connection.chat.activeConversationId {
                                    Circle()
                                        .fill(NOCOAITheme.success)
                                        .frame(width: 8, height: 8)
                                        .shadow(color: NOCOAITheme.success.opacity(0.6), radius: 4)
                                }
                            }
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 8)
                            .animation(
                                .spring(response: 0.4, dampingFraction: 0.82).delay(Double(min(index, 8)) * 0.03),
                                value: appeared
                            )
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let id = connection.chat.filteredConversations[index].id
                            Task { await connection.chat.deleteConversation(id) }
                        }
                    }
                }

                if !connection.chat.keyboardConversations.isEmpty {
                    Section("Tastatur") {
                        ForEach(connection.chat.keyboardConversations) { convo in
                            Button {
                                HapticService.selection()
                                Task {
                                    await connection.chat.selectConversation(convo.id)
                                    dismiss()
                                }
                            } label: {
                                Label(convo.title, systemImage: "keyboard")
                            }
                        }
                    }
                }
            }
            .searchable(text: Binding(
                get: { connection.chat.searchText },
                set: { connection.chat.searchText = $0 }
            ), prompt: "Chats suchen")
            .navigationTitle("Chats")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .onAppear {
                withAnimation { appeared = true }
            }
        }
    }
}

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
                     ? "Zusammenfassung läuft automatisch…"
                     : "Über ~35 Nachrichten — verdichtet automatisch oder tippe hier.")
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

private struct AgentInlineConfirmBar: View {
    let title: String
    let detail: String
    var onAllow: () -> Void
    var onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bestätigung nötig")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(red: 0.98, green: 0.72, blue: 0.28))
            Text(title)
                .font(.subheadline.weight(.semibold))
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            HStack(spacing: 10) {
                Button(action: onDeny) {
                    Text("Ablehnen")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                Button(action: onAllow) {
                    Text("Erlauben")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(NOCOAITheme.accent))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(red: 0.98, green: 0.72, blue: 0.28).opacity(0.45), lineWidth: 1)
        )
    }
}
