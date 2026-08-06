import SwiftUI

/// Premium Agent dashboard — plans, progress, confirmations, history.
struct AgentDashboardView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @StateObject private var session = AgentSessionController()
    @State private var appear = false
    @FocusState private var goalFocused: Bool

    var body: some View {
        ZStack {
            atmosphere
            VStack(spacing: 0) {
                topChrome
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                ScrollView {
                    VStack(spacing: 16) {
                        composeCard
                        modeRow
                        skillRow
                        qualityRow
                        if let task = session.activeTask, let label = task.activeModelLabel, !label.isEmpty {
                            Text("NOCO nutzt: \(label)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(task.phaseColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let pending = session.activeTask?.pendingConfirm {
                            confirmCard(pending)
                        }
                        if let task = session.activeTask {
                            activeTaskCard(task)
                        }
                        projectsSection
                        historySection
                        skillsHint
                        NavigationLink {
                            ComputerControlView().environmentObject(connection)
                        } label: {
                            HStack {
                                Image(systemName: "hand.point.up.left.fill")
                                Text("Computer Control")
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
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
            session.bind { connection.companionAPI() }
            if let draft = connection.pendingAgentDraft?.trimmingCharacters(in: .whitespacesAndNewlines), !draft.isEmpty {
                session.draftGoal = draft
                connection.pendingAgentDraft = nil
                goalFocused = true
                HapticService.open()
            }
            session.startPolling()
            Task { await session.refresh() }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.84)) { appear = true }
        }
        .onDisappear { session.stopPolling() }
        .alert("NOCO Agent", isPresented: Binding(
            get: { session.lastError != nil },
            set: { if !$0 { session.clearError() } }
        )) {
            Button("OK", role: .cancel) { session.clearError() }
        } message: {
            Text(session.lastError ?? "")
        }
    }

    private var atmosphere: some View {
        ZStack {
            IntelligenceAtmosphere().opacity(0.9)
            RadialGradient(
                colors: [session.mode.accent.opacity(scheme == .dark ? 0.22 : 0.12), .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 340
            )
            .animation(.easeInOut(duration: 0.45), value: session.mode)
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
                Text("NOCO Agent")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(session.activeTask.map { "\($0.phaseTitle) · \(session.statusLine)" } ?? session.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            AgentCoreOrb(
                isActive: session.isWorking
                    || session.activeTask?.status == "running"
                    || session.activeTask?.status == "planning",
                progress: Double(session.activeTask?.progress ?? 0),
                phaseColor: session.activeTask?.phaseColor ?? session.mode.accent
            )
            .scaleEffect(0.85)
        }
        .opacity(appear ? 1 : 0)
    }

    private var composeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Neue Aufgabe", systemImage: "brain.head.profile")
                    .font(.subheadline.weight(.semibold))

                TextField("Was soll NOCO erledigen?", text: $session.draftGoal, axis: .vertical)
                    .lineLimit(2...5)
                    .focused($goalFocused)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                    )

                Button {
                    goalFocused = false
                    Task { await session.startGoal() }
                } label: {
                    HStack {
                        if session.isWorking {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text(session.isWorking ? "Arbeitet…" : "Planen & starten")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(session.mode.accent.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.white)
                }
                .disabled(session.isWorking || session.draftGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !connection.isOnline)
                .opacity(connection.isOnline ? 1 : 0.5)
            }
        }
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 12)
    }

    private var modeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(AgentMode.allCases) { mode in
                    Button {
                        HapticService.selection()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            session.mode = mode
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: mode.systemImage)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(mode.title).font(.caption.weight(.bold))
                                Text(mode.subtitle).font(.caption2).opacity(0.75)
                            }
                        }
                        .foregroundStyle(session.mode == mode ? Color.white : Color.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background {
                            if session.mode == mode {
                                Capsule().fill(mode.accent.gradient)
                            } else {
                                Capsule().fill(.ultraThinMaterial)
                            }
                        }
                    }
                    .buttonStyle(IntelligencePressStyle(haptic: { HapticService.soft() }))
                }
            }
        }
    }

    private var skillRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Skill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AgentKind.allCases) { kind in
                        Button {
                            HapticService.selection()
                            session.kind = kind
                        } label: {
                            Text(kind.title)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(session.kind == kind
                                        ? Color(red: 0.35, green: 0.78, blue: 0.72).opacity(0.85)
                                        : Color.primary.opacity(0.06))
                                )
                                .foregroundStyle(session.kind == kind ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var qualityRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Modell-Profil")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AgentQualityProfile.allCases) { profile in
                        Button {
                            HapticService.selection()
                            session.qualityProfile = profile
                        } label: {
                            Text(profile.title)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(session.qualityProfile == profile
                                        ? NOCOAITheme.accent.opacity(0.85)
                                        : Color.primary.opacity(0.06))
                                )
                                .foregroundStyle(session.qualityProfile == profile ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func confirmCard(_ pending: AgentPendingConfirm) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(pending.title, systemImage: "exclamationmark.shield.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.orange)
                Text(pending.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button {
                        Task { await session.confirm(allow: false) }
                    } label: {
                        Text("Abbrechen")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    Button {
                        Task { await session.confirm(allow: true) }
                    } label: {
                        Text("Erlauben")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.orange.gradient, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }

    private func activeTaskCard(_ task: AgentTask) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.goal)
                            .font(.headline)
                        Text("\(task.statusEnum.label) · \(task.progress)%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if task.status == "running" || task.status == "planning" {
                        ProgressView()
                    }
                }

                ProgressView(value: Double(task.progress), total: 100)
                    .tint(task.phaseColor)

                if let notes = task.qualityNotes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !task.planSummary.isEmpty {
                    Text(task.planSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(task.steps) { step in
                        stepRow(step, current: task.currentStepIndex)
                    }
                }

                if let result = task.resultSummary, !result.isEmpty {
                    Text(result)
                        .font(.subheadline)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(session.mode.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if !task.artifacts.isEmpty {
                    Text("Dateien: " + task.artifacts.map(\.name).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    if task.status != "completed" && task.status != "cancelled" {
                        Button("Abbrechen") {
                            Task { await session.cancelActive() }
                        }
                        .font(.caption.weight(.semibold))
                    }
                    Spacer()
                    if task.status == "completed", let result = task.resultSummary, !result.isEmpty {
                        Button("Im Chat") {
                            connection.continueInChat(
                                draft: "Agent-Ergebnis zu „\(task.goal)“:\n\n\(result)\n\nBitte fasse zusammen und schlage Nächstes vor."
                            )
                        }
                        .font(.caption.weight(.semibold))
                    }
                    if task.status == "draft" {
                        Button("Weiterlaufen") {
                            Task { await session.continueRun() }
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
            }
        }
    }

    private func stepRow(_ step: AgentStep, current: Int) -> some View {
        let icons = ["🧠", "🔎", "📋", "⚙️", "✅"]
        let icon = icons[min(step.index, icons.count - 1)]
        return HStack(alignment: .top, spacing: 10) {
            Text(icon)
                .font(.caption)
                .padding(.top, 2)
            Circle()
                .fill(stepColor(step.status))
                .frame(width: 10, height: 10)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(step.index + 1). \(step.title)")
                    .font(.subheadline.weight(step.index == current ? .bold : .medium))
                if !step.reason.isEmpty {
                    Text(step.reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let result = step.result, !result.isEmpty {
                    Text(result.prefix(180))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(step.status)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .opacity(step.status == "pending" ? 0.7 : 1)
    }

    private var projectsSection: some View {
        Group {
            if !session.projects.isEmpty || !session.memoryFacts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Projekte & Gedächtnis")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(session.projects.prefix(6)) { project in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.title)
                                .font(.subheadline.weight(.medium))
                            Text(project.goal)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            ProgressView(value: Double(project.progress), total: 100)
                                .tint(Color(red: 0.35, green: 0.78, blue: 0.72))
                        }
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    ForEach(session.memoryFacts.prefix(4)) { fact in
                        Text("• \(fact.text)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func stepColor(_ status: String) -> Color {
        switch status {
        case "completed": return NOCOAITheme.success
        case "running": return session.mode.accent
        case "needs_confirm": return .orange
        case "failed", "denied": return NOCOAITheme.danger
        default: return .secondary.opacity(0.4)
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Verlauf")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if session.tasks.isEmpty {
                Text("Noch keine Agent-Aufgaben")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            ForEach(session.tasks.prefix(12)) { task in
                Button {
                    session.select(task)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.goal)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                            Text("\(task.statusEnum.label) · \(task.progress)%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }

    private var skillsHint: some View {
        Text("Skills: Coding · Study · Creative · Life · Travel · Finance · Smart Home")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }
}
