import SwiftUI

/// Remote console for Windows Computer Control — permissions, timeline, goal handoff.
struct ComputerControlView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @StateObject private var control = ComputerControlController()
    @StateObject private var agent = AgentSessionController()
    @State private var appear = false
    @FocusState private var goalFocused: Bool

    private let pipeline: [(id: String, title: String, icon: String)] = [
        ("analyzing_screen", "Analysiere Bildschirm", "brain.head.profile"),
        ("recognizing", "Erkenne Elemente", "eye"),
        ("executing", "Führe Aktion aus", "hand.tap"),
        ("done", "Aufgabe abgeschlossen", "checkmark.circle.fill"),
    ]

    var body: some View {
        ZStack {
            atmosphere
            VStack(spacing: 0) {
                topChrome
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                ScrollView {
                    VStack(spacing: 16) {
                        statusCard
                        permissionCard
                        pipelineCard
                        goalCard
                        if let pending = agent.activeTask?.pendingConfirm {
                            confirmCard(pending)
                        }
                        if let task = agent.activeTask {
                            agentProgress(task)
                        }
                        actionLog
                        limitations
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 40)
                }
            }
        }
        .nocoBackground()
        .navigationBarHidden(true)
        .onAppear {
            control.bind { connection.companionAPI() }
            agent.bind { connection.companionAPI() }
            control.startPolling()
            agent.startPolling()
            Task {
                await control.refresh()
                await agent.refresh()
            }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.84)) { appear = true }
        }
        .onDisappear {
            control.stopPolling()
            agent.stopPolling()
        }
        .alert("Computer Control", isPresented: Binding(
            get: { control.lastError != nil },
            set: { if !$0 { control.clearError() } }
        )) {
            Button("OK", role: .cancel) { control.clearError() }
        } message: {
            Text(control.lastError ?? "")
        }
    }

    private var atmosphere: some View {
        ZStack {
            IntelligenceAtmosphere().opacity(0.85)
            RadialGradient(
                colors: [
                    (control.status?.phaseColor ?? Color(red: 0.35, green: 0.55, blue: 1.0))
                        .opacity(scheme == .dark ? 0.22 : 0.12),
                    .clear,
                ],
                center: .top,
                startRadius: 8,
                endRadius: 360
            )
            .animation(.easeInOut(duration: 0.45), value: control.status?.phase)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var topChrome: some View {
        HStack(spacing: 12) {
            Button {
                HapticService.soft()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Computer Control")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(control.status?.phaseLabel ?? "Windows Companion")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            AgentCoreOrb(
                isActive: control.isWorking || (control.status?.enabled == true && control.status?.paused != true),
                progress: Double(agent.activeTask?.progress ?? (control.status?.enabled == true ? 35 : 0)),
                phaseColor: control.status?.phaseColor ?? Color(red: 0.35, green: 0.55, blue: 1.0)
            )
            .scaleEffect(0.8)
        }
        .opacity(appear ? 1 : 0)
    }

    private var statusCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(control.status?.enabled == true ? "Aktiv" : "Geschützt", systemImage: "desktopcomputer")
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    if control.status?.paused == true {
                        Text("Pausiert")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                Text(control.status?.currentAction ?? "NOCO steuert den PC nur mit deiner Freigabe.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    if control.status?.paused == true {
                        Button("Fortsetzen") {
                            Task { await control.resume() }
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Pause") {
                            Task { await control.pause() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(control.status?.enabled != true)
                    }
                    Button("Bildschirm analysieren") {
                        Task { await control.analyzeScreen() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(control.isWorking)
                }
            }
        }
    }

    private var permissionCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Berechtigungen", systemImage: "lock.shield.fill")
                    .font(.subheadline.weight(.bold))
                Toggle("Computer Control erlauben", isOn: Binding(
                    get: { control.status?.enabled ?? false },
                    set: { newValue in Task { await control.setEnabled(newValue) } }
                ))
                Text("Maus, Tastatur und Programme werden erst nach Freigabe gesteuert. Kritische Schritte brauchen zusätzlich Bestätigung.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pipelineCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ablauf")
                    .font(.subheadline.weight(.semibold))
                ForEach(Array(pipeline.enumerated()), id: \.offset) { idx, step in
                    let active = (control.status?.phase ?? "") == step.id
                    let done = control.status?.phase == "done" || pipelineActiveIndex >= idx
                    HStack(spacing: 12) {
                        Image(systemName: step.icon)
                            .foregroundStyle(active ? (control.status?.phaseColor ?? .blue) : .secondary)
                            .frame(width: 22)
                        Text(step.title)
                            .font(.subheadline.weight(active ? .bold : .regular))
                        Spacer()
                        if done || active {
                            Image(systemName: done && !active ? "checkmark.circle.fill" : "circle.fill")
                                .font(.caption)
                                .foregroundStyle(active ? (control.status?.phaseColor ?? .blue) : NOCOAITheme.success)
                        }
                    }
                    .padding(.vertical, 4)
                    .opacity(active ? 1 : 0.7)
                    if idx < pipeline.count - 1 {
                        Image(systemName: "arrow.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 6)
                    }
                }
            }
        }
    }

    private var pipelineActiveIndex: Int {
        let phase = control.status?.phase ?? "idle"
        return pipeline.firstIndex(where: { $0.id == phase }) ?? -1
    }

    private var goalCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ziel für den PC")
                    .font(.subheadline.weight(.semibold))
                TextField("z. B. Öffne Notepad und tippe Hallo", text: $control.draftGoal, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($goalFocused)
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Button {
                    Task { await control.startComputerGoal(via: agent) }
                } label: {
                    Text("Mit Computer Control starten")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(red: 0.35, green: 0.55, blue: 1.0).gradient, in: Capsule())
                        .foregroundStyle(.white)
                }
                .disabled(control.draftGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || control.status?.enabled != true)
                .opacity(control.status?.enabled == true ? 1 : 0.5)
            }
        }
    }

    private func confirmCard(_ pending: AgentPendingConfirm) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(pending.title, systemImage: "exclamationmark.shield.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.orange)
                Text(pending.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("Abbrechen") { Task { await agent.confirm(allow: false) } }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                    Button("Erlauben") { Task { await agent.confirm(allow: true) } }
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.orange.gradient, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private func agentProgress(_ task: AgentTask) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(task.goal)
                    .font(.headline)
                Text("\(task.phaseTitle) · \(task.progress)%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(task.progress), total: 100)
                    .tint(task.phaseColor)
                ForEach(task.steps.prefix(6)) { step in
                    HStack {
                        Text(step.status == "completed" ? "✓" : (step.status == "running" ? "→" : "·"))
                        Text(step.title)
                            .font(.caption)
                        Spacer()
                    }
                }
            }
        }
    }

    private var actionLog: some View {
        Group {
            if let actions = control.status?.recentActions, !actions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Aktionsverlauf")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(actions.prefix(10)) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .font(.caption.weight(.semibold))
                            Text(entry.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }

    private var limitations: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(control.status?.limitations.prefix(4) ?? [
                "Volle Steuerung läuft auf dem Windows Companion.",
                "Kritische Aktionen brauchen Bestätigung."
            ], id: \.self) { line in
                Text("• \(line)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
