import SwiftUI

/// Central + panel: depth (Auto / Think / Flash) + grouped tools.
struct PlusToolsPanel: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var onCamera: () -> Void
    var onLibrary: () -> Void
    var onDocument: () -> Void
    var onFile: () -> Void
    var onWritingTools: () -> Void

    @State private var appear = false

    private let depthModes: [AIMode] = [.auto, .think, .flash]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intelligenceHeader
                    depthSection
                    groupSection("Erstellen", tiles: [
                        .init("Bild", "paintbrush.pointed.fill", Color(red: 0.95, green: 0.55, blue: 0.78)) {
                            connection.handoffToImages(prompt: "")
                            dismiss()
                        },
                        .init("Schreiben", "pencil.and.outline", Color(red: 0.62, green: 0.55, blue: 0.98)) {
                            dismiss(); onWritingTools()
                        }
                    ])
                    groupSection("Medien", tiles: [
                        .init("Kamera", "camera.fill", Color(red: 0.35, green: 0.75, blue: 1)) {
                            dismiss(); onCamera()
                        },
                        .init("Foto", "photo.on.rectangle", Color(red: 0.45, green: 0.85, blue: 0.7)) {
                            dismiss(); onLibrary()
                        },
                        .init("Datei", "folder.fill", Color(red: 0.75, green: 0.65, blue: 0.45)) {
                            dismiss(); onFile()
                        },
                        .init("Dokument", "doc.text.fill", Color(red: 0.55, green: 0.7, blue: 0.95)) {
                            dismiss(); onDocument()
                        }
                    ])
                    groupSection("KI-Werkzeuge", tiles: [
                        .init("Internet", "globe", Color(red: 0.35, green: 0.65, blue: 0.95)) {
                            connection.chat.armLiveKnowledge(.web)
                            HapticService.open()
                            dismiss()
                        },
                        .init("Agent", "cpu.fill", Color(red: 0.35, green: 0.78, blue: 0.72)) {
                            connection.chat.setMode(.agent)
                            HapticService.open()
                            dismiss()
                        },
                        .init("Voice AI", "waveform.circle.fill", Color(red: 0.45, green: 0.85, blue: 0.7)) {
                            connection.speak.openUI()
                            dismiss()
                        },
                        .init("Live Screen", "rectangle.inset.filled.and.person.filled", Color(red: 0.98, green: 0.55, blue: 0.35)) {
                            connection.pendingOpenLiveScreen = true
                            connection.pendingTab = 2
                            dismiss()
                        }
                    ])
                }
                .padding(18)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 28)
                .scaleEffect(appear ? 1 : 0.97)
            }
            .nocoBackground()
            .overlay {
                FloatingIntelligenceDots(count: 6)
                    .opacity(0.14)
                    .allowsHitTesting(false)
            }
            .navigationTitle("Werkzeuge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                            appear = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            dismiss()
                        }
                    }
                }
            }
        }
        .presentationDetents([.height(680), .medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground {
            ZStack {
                Color.black.opacity(0.28)
                IntelligenceAtmosphere()
                    .opacity(0.55)
                NOCORainbowFlowLine(height: 1.5)
                    .padding(.horizontal, 40)
                    .offset(y: -180)
                    .opacity(0.35)
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.45, dampingFraction: 0.86)) {
                appear = true
            }
        }
        .onDisappear {
            appear = false
        }
    }

    private var intelligenceHeader: some View {
        HStack(spacing: 12) {
            NOCOIntelligenceCore(energy: .idle, size: .compact, systemImage: "sparkles")
                .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text("NOCO Intelligence")
                    .font(.subheadline.weight(.bold))
                Text("Werkzeuge mit lebendiger KI verbinden")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                NOCORainbowFlowLine(height: 2)
                    .frame(maxWidth: 160)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .nocoGlass(cornerRadius: 18)
    }

    private var depthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Denkmodus")
                .font(.subheadline.weight(.bold))
            Text("Nur für Chat & Voice AI — wählt Tiefe und Tempo, keine Extra-Tools.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(depthModes) { mode in
                    Button {
                        HapticService.selection()
                        connection.chat.setMode(mode)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: mode.systemImage)
                                .font(.system(size: 16, weight: .semibold))
                            Text(mode.label)
                                .font(.caption.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(connection.chat.mode == mode
                                      ? mode.accentColor.opacity(0.92)
                                      : Color.primary.opacity(0.05))
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(mode.accentColor.opacity(connection.chat.mode == mode ? 0.5 : 0.15), lineWidth: 1)
                        )
                        .foregroundStyle(connection.chat.mode == mode ? .white : .primary)
                    }
                    .buttonStyle(IntelligencePressStyle(haptic: { HapticService.soft() }))
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: connection.chat.mode)
        }
    }

    private struct Tile {
        let title: String
        let icon: String
        let accent: Color
        let action: () -> Void
        init(_ title: String, _ icon: String, _ accent: Color, action: @escaping () -> Void) {
            self.title = title; self.icon = icon; self.accent = accent; self.action = action
        }
    }

    private func groupSection(_ title: String, tiles: [Tile]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                    Button(action: tile.action) {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(tile.accent.opacity(0.16))
                                    .frame(width: 36, height: 36)
                                Image(systemName: tile.icon)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(tile.accent)
                            }
                            Text(tile.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(
                                            AngularGradient(
                                                colors: [
                                                    tile.accent.opacity(0.55),
                                                    NOCORainbow.violet.opacity(0.25),
                                                    tile.accent.opacity(0.15),
                                                    NOCORainbow.blue.opacity(0.3)
                                                ],
                                                center: .center
                                            ),
                                            lineWidth: 1
                                        )
                                )
                                .shadow(color: tile.accent.opacity(0.12), radius: 10, y: 4)
                        )
                    }
                    .buttonStyle(IntelligencePressStyle(haptic: { HapticService.soft() }))
                }
            }
        }
    }
}
