import SwiftUI

struct ImagesHubView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme
    @State private var appear = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    IntelligenceHeroBanner(
                        title: "Bildideen",
                        subtitle: "Beschreiben → auf dem PC erzeugen",
                        online: connection.isOnline
                    )
                    .opacity(appear ? 1 : 0)

                    GlassCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Neuer Prompt").font(.headline)
                                Spacer()
                                Image(systemName: "paintbrush.pointed.fill")
                                    .foregroundStyle(NOCOAITheme.accent)
                                    .symbolEffect(.pulse, options: .repeating.speed(0.4))
                            }

                            TextField("Beschreibe dein Bild…", text: Binding(
                                get: { connection.images.prompt },
                                set: { connection.images.prompt = $0 }
                            ), axis: .vertical)
                                .lineLimit(3...6)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.primary.opacity(0.06))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .stroke(NOCOAITheme.glowPrimary.opacity(0.2), lineWidth: 1)
                                        )
                                )

                            if connection.images.isGenerating {
                                IntelligenceGeneratingOverlay(
                                    progress: connection.images.progress,
                                    status: connection.images.statusText
                                )
                                .frame(maxWidth: .infinity)
                            }

                            Button {
                                HapticService.medium()
                                Task { await connection.images.generate(conversationId: connection.chat.activeConversationId) }
                            } label: {
                                HStack {
                                    Image(systemName: "sparkles")
                                    Text(connection.images.isGenerating ? "Generiere…" : "Bild erstellen")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [NOCOAITheme.accent, NOCOAITheme.accentSecondary],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                )
                                .foregroundStyle(.white)
                                .shadow(color: NOCOAITheme.glowPrimary.opacity(0.4), radius: 12)
                            }
                            .disabled(connection.images.prompt.isEmpty || connection.images.isGenerating || !connection.isOnline)
                            .opacity(connection.images.prompt.isEmpty || !connection.isOnline ? 0.5 : 1)
                        }
                    }

                    if let url = connection.images.lastImageURL {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Letztes Bild").font(.headline)
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let img):
                                        img.resizable().scaledToFit()
                                            .clipShape(RoundedRectangle(cornerRadius: 16))
                                            .shadow(color: NOCOAITheme.glowPrimary.opacity(0.25), radius: 14)
                                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                                    default:
                                        ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                                    }
                                }
                            }
                        }
                    }

                    if !connection.images.gallery.isEmpty {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Galerie").font(.headline)
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                    ForEach(Array(connection.images.gallery.enumerated()), id: \.element.id) { index, item in
                                        if let url = item.url {
                                            AsyncImage(url: url) { phase in
                                                switch phase {
                                                case .success(let img): img.resizable().scaledToFill()
                                                default: Color.secondary.opacity(0.2)
                                                }
                                            }
                                            .frame(height: 120)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(NOCOAITheme.glowPrimary.opacity(0.2), lineWidth: 1)
                                            )
                                            .opacity(appear ? 1 : 0)
                                            .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(Double(index) * 0.04), value: appear)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .nocoBackground()
            .overlay {
                FloatingIntelligenceDots(count: 8)
                    .opacity(0.25)
                    .allowsHitTesting(false)
            }
            .navigationTitle("Bildideen")
            .task {
                await connection.refreshGallery()
                withAnimation(.spring(response: 0.55, dampingFraction: 0.84)) {
                    appear = true
                }
            }
        }
    }
}
