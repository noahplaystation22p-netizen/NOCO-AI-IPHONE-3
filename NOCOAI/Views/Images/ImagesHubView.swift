import SwiftUI

struct ImagesHubView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Bild generieren").font(.headline)
                            TextField("Beschreibe dein Bild…", text: Binding(
                                get: { connection.images.prompt },
                                set: { connection.images.prompt = $0 }
                            ), axis: .vertical)
                                .lineLimit(3...6)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))

                            if connection.images.isGenerating {
                                ProgressView(value: connection.images.progress)
                                Text(connection.images.statusText).font(.caption).foregroundStyle(.secondary)
                            }

                            Button {
                                Task { await connection.images.generate(conversationId: connection.chat.activeConversationId) }
                            } label: {
                                Text(connection.images.isGenerating ? "Generiere…" : "Bild erstellen")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(NOCOAITheme.accent)
                            .disabled(connection.images.prompt.isEmpty || connection.images.isGenerating)
                        }
                    }

                    if let url = connection.images.lastImageURL {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Letztes Bild").font(.headline)
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let img): img.resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 16))
                                    default: ProgressView().frame(maxWidth: .infinity, minHeight: 200)
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
                                    ForEach(connection.images.gallery) { item in
                                        if let url = item.url {
                                            AsyncImage(url: url) { phase in
                                                switch phase {
                                                case .success(let img): img.resizable().scaledToFill()
                                                default: Color.secondary.opacity(0.2)
                                                }
                                            }
                                            .frame(height: 120)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
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
            .navigationTitle("Bilder")
            .task { await connection.refreshGallery() }
        }
    }
}
