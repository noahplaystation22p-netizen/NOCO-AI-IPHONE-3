import SwiftUI
import UIKit

struct ImagesHubView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme
    @State private var appear = false
    @State private var selectedItem: GeneratedImageItem?
    @State private var reveal = false
    @FocusState private var promptFocused: Bool
    @State private var draftPrompt = ""

    private let ideaPrompts = [
        "Neon-Stadt bei Regen, cinematic",
        "Soft portrait, studio light",
        "Fantasy forest, golden hour",
        "Minimal product shot, white"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    IntelligenceHeroBanner(
                        title: "Bildideen",
                        subtitle: "Beschreiben → PC erzeugt mit Stable Diffusion",
                        online: connection.isOnline
                    )
                    .opacity(appear ? 1 : 0)

                    IntelligenceWaveRibbon()
                        .frame(height: 26)
                        .padding(.horizontal, 8)

                    createCard

                    NavigationLink {
                        MagischerRadiererView()
                            .environmentObject(connection)
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.45, green: 0.55, blue: 1),
                                                Color(red: 0.85, green: 0.4, blue: 0.9)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 44, height: 44)
                                Image(systemName: "eraser.fill")
                                    .foregroundStyle(.white)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Magischer Radierer")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("Bemalen → entfernen oder ändern")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(NOCOAITheme.glowPrimary.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(IntelligencePressStyle(haptic: { HapticService.open() }))

                    resultCard
                    galleryCard
                }
                .padding(20)
            }
            .nocoBackground()
            .overlay {
                // Skip heavy overlays while generating — big lag win on older iPhones
                if !connection.images.isGenerating {
                    FloatingIntelligenceDots(count: 2)
                        .opacity(0.18)
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle("Bildideen")
            .sheet(item: $selectedItem) { item in
                ImageDetailSheet(item: item)
                    .environmentObject(connection)
            }
            .onChange(of: connection.pendingGalleryImageId) { _, _ in
                focusPendingGalleryImage()
            }
            .onChange(of: connection.pendingGalleryImageURL) { _, _ in
                focusPendingGalleryImage()
            }
            .onAppear {
                focusPendingGalleryImage()
            }
            .task {
                draftPrompt = connection.images.prompt
                await connection.refreshGallery()
                focusPendingGalleryImage()
                withAnimation(.spring(response: 0.55, dampingFraction: 0.84)) {
                    appear = true
                }
            }
            .onChange(of: connection.images.phase) { _, phase in
                if phase == .done {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
                        reveal = true
                    }
                }
            }
            .alert(
                "Fotos",
                isPresented: Binding(
                    get: { connection.images.saveMessage != nil },
                    set: { if !$0 { connection.images.saveMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { connection.images.saveMessage = nil }
            } message: {
                Text(connection.images.saveMessage ?? "")
            }
        }
    }

    private func focusPendingGalleryImage() {
        let id = connection.pendingGalleryImageId
        let url = connection.pendingGalleryImageURL
        guard id != nil || url != nil else { return }

        if let id, let match = connection.images.gallery.first(where: { $0.id == id }) {
            selectedItem = match
            connection.clearPendingGalleryFocus()
            return
        }
        if let url, let match = connection.images.gallery.first(where: {
            $0.url?.absoluteString == url.absoluteString ||
            $0.url?.path == url.path ||
            ($0.url?.lastPathComponent == url.lastPathComponent && !url.lastPathComponent.isEmpty)
        }) {
            selectedItem = match
            connection.clearPendingGalleryFocus()
            return
        }
        // Fallback: open latest gallery item if chat pointed at something not yet indexed
        if let newest = connection.images.gallery.first {
            selectedItem = newest
            connection.clearPendingGalleryFocus()
        }
    }

    // MARK: - Create

    private var createCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Neue Bildidee").font(.headline)
                    Spacer()
                    Image(systemName: "paintbrush.pointed.fill")
                        .foregroundStyle(NOCOAITheme.accent)
                        .symbolEffect(.pulse, options: .repeating.speed(0.4))
                }

                TextField("Beschreibe dein Bild…", text: $draftPrompt, axis: .vertical)
                .lineLimit(3...6)
                .focused($promptFocused)
                .submitLabel(.done)
                .onSubmit { promptFocused = false }
                .disabled(connection.images.isGenerating)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(NOCOAITheme.glowPrimary.opacity(0.25), lineWidth: 1)
                        )
                )

                if !connection.images.isGenerating {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ideaPrompts, id: \.self) { tip in
                                Button {
                                    draftPrompt = tip
                                    connection.images.prompt = tip
                                    HapticService.selection()
                                } label: {
                                    Text(tip)
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(
                                            Capsule()
                                                .fill(NOCOAITheme.accent.opacity(0.12))
                                                .overlay(Capsule().stroke(NOCOAITheme.glowPrimary.opacity(0.28), lineWidth: 1))
                                        )
                                        .foregroundStyle(NOCOAITheme.accent)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if connection.images.isGenerating {
                    ImageCreationTheater(
                        progress: connection.images.progress,
                        status: connection.images.statusText,
                        insight: connection.images.insightText,
                        etaSeconds: connection.images.etaSeconds
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))

                    Button(role: .destructive) {
                        Task { await connection.images.cancel() }
                    } label: {
                        Label("Abbrechen", systemImage: "xmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                } else {
                    Button {
                        promptFocused = false
                        connection.images.prompt = draftPrompt
                        reveal = false
                        HapticService.send()
                        connection.images.startGenerate()
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Auf dem PC erstellen")
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
                    .disabled(draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !connection.isOnline)
                    .opacity(draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !connection.isOnline ? 0.5 : 1)

                    Text("Du kannst die App verlassen — du bekommst eine Mitteilung, wenn das Bild fertig ist.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if connection.images.phase == .error, !connection.images.statusText.isEmpty {
                    Text(connection.images.statusText)
                        .font(.caption)
                        .foregroundStyle(NOCOAITheme.danger)
                }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.84), value: connection.images.isGenerating)
    }

    // MARK: - Result

    @ViewBuilder
    private var resultCard: some View {
        if connection.images.lastImageData != nil || connection.images.lastImageURL != nil {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Ergebnis").font(.headline)
                        Spacer()
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(NOCOAITheme.success)
                            .symbolEffect(.bounce, value: reveal)
                    }

                    resultImage
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            NOCOAITheme.glowPrimary.opacity(0.5),
                                            NOCOAITheme.glowAccent.opacity(0.3)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.2
                                )
                        )
                        .shadow(color: NOCOAITheme.glowPrimary.opacity(0.3), radius: 16, y: 6)
                        .scaleEffect(reveal ? 1 : 0.94)
                        .opacity(reveal ? 1 : 0.4)
                        .blur(radius: reveal ? 0 : 8)

                    if !connection.images.lastPrompt.isEmpty {
                        Text(connection.images.lastPrompt)
                            .font(.caption)
                            .foregroundStyle(NOCOAITheme.secondaryText(for: scheme))
                            .lineLimit(3)
                    }

                    HStack(spacing: 10) {
                        Button {
                            Task { await connection.images.saveLastToPhotos() }
                        } label: {
                            Label("In Fotos", systemImage: "square.and.arrow.down.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(NOCOAITheme.accent.opacity(0.16))
                                )
                                .foregroundStyle(NOCOAITheme.accent)
                        }
                        .buttonStyle(.plain)

                        if let url = connection.images.lastImageURL {
                            ShareLink(item: url) {
                                Label("Teilen", systemImage: "square.and.arrow.up")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Color.primary.opacity(0.06))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .intelligenceMessageArrive()
            .onAppear {
                if connection.images.phase == .done || connection.images.lastImageURL != nil {
                    reveal = true
                }
            }
        }
    }

    @ViewBuilder
    private var resultImage: some View {
        if let data = connection.images.lastImageData, let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
        } else if let url = connection.images.lastImageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFit()
                case .failure:
                    Label("Bild nicht ladbar", systemImage: "exclamationmark.triangle")
                        .frame(maxWidth: .infinity, minHeight: 180)
                default:
                    ProgressView().frame(maxWidth: .infinity, minHeight: 180)
                }
            }
        }
    }

    // MARK: - Gallery

    @ViewBuilder
    private var galleryCard: some View {
        if !connection.images.gallery.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Galerie").font(.headline)
                        Spacer()
                        Text("\(connection.images.gallery.count)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(NOCOAITheme.accent)
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(Array(connection.images.gallery.enumerated()), id: \.element.id) { index, item in
                            Button {
                                selectedItem = item
                                HapticService.open()
                            } label: {
                                galleryThumb(item)
                            }
                            .buttonStyle(.plain)
                            .opacity(appear ? 1 : 0)
                            .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(Double(index) * 0.04), value: appear)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func galleryThumb(_ item: GeneratedImageItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let data = item.localData, let ui = UIImage(data: data) {
                    Image(uiImage: ui).resizable().scaledToFill()
                } else if let url = item.url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: Color.secondary.opacity(0.2)
                        }
                    }
                } else {
                    Color.secondary.opacity(0.2)
                }
            }
            .frame(height: 130)
            .frame(maxWidth: .infinity)
            .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            Text(item.prompt)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(NOCOAITheme.glowPrimary.opacity(0.22), lineWidth: 1)
        )
    }
}

// MARK: - Detail

private struct ImageDetailSheet: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.dismiss) private var dismiss
    let item: GeneratedImageItem

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    detailImage
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: NOCOAITheme.glowPrimary.opacity(0.25), radius: 16)

                    Text(item.prompt)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        Task {
                            await connection.images.saveItemToPhotos(item)
                            dismiss()
                        }
                    } label: {
                        Label("In Aufnahmen speichern", systemImage: "photo.on.rectangle.angled")
                            .font(.headline)
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
                    }
                    .buttonStyle(.plain)

                    if let url = item.url {
                        ShareLink(item: url) {
                            Label("Teilen", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    }
                }
                .padding(20)
            }
            .nocoBackground()
            .navigationTitle("Bild")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var detailImage: some View {
        if let data = item.localData, let ui = UIImage(data: data) {
            Image(uiImage: ui).resizable().scaledToFit()
        } else if let url = item.url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFit()
                default: ProgressView().frame(minHeight: 220)
                }
            }
        }
    }
}
