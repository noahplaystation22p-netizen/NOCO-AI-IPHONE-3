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
    @State private var openEraser = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    IntelligenceHeroBanner(
                        title: "Bilder",
                        subtitle: connection.isOnline
                            ? "Beschreiben ? NOCO erzeugt auf dem PC"
                            : "Companion verbinden, dann erzeugen",
                        online: connection.isOnline
                    )
                    .opacity(appear ? 1 : 0)

                    IntelligenceWaveRibbon()
                        .frame(height: 26)
                        .padding(.horizontal, 8)

                    createCard

                    engineCard

                    Button {
                        HapticService.open()
                        openEraser = true
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
                                Text("Bemalen ? Anweisung tippen ? fertig")
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
                    .navigationDestination(isPresented: $openEraser) {
                        MagischerRadiererView()
                            .environmentObject(connection)
                    }

                    resultCard
                    galleryCard
                }
                .padding(20)
            }
            .nocoBackground()
            .overlay {
                // Skip heavy overlays while generating ? big lag win on older iPhones
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
            .onChange(of: connection.pendingOpenEraser) { _, open in
                if open {
                    openEraser = true
                    connection.pendingOpenEraser = false
                }
            }
            .onChange(of: connection.pendingGalleryImageURL) { _, _ in
                focusPendingGalleryImage()
            }
            .onAppear {
                focusPendingGalleryImage()
                if connection.pendingOpenEraser {
                    openEraser = true
                    connection.pendingOpenEraser = false
                }
            }
            .task {
                draftPrompt = connection.images.prompt
                await connection.refreshGallery()
                focusPendingGalleryImage()
                withAnimation(.spring(response: 0.55, dampingFraction: 0.84)) {
                    appear = true
                }
            }
            .onChange(of: connection.images.prompt) { _, newPrompt in
                if !newPrompt.isEmpty, draftPrompt != newPrompt {
                    draftPrompt = newPrompt
                }
            }
            .onChange(of: connection.images.phase) { _, phase in
                if phase == .done {
                    HapticService.success()
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
                        reveal = true
                    }
                } else if phase == .rendering {
                    HapticService.selection()
                } else if phase == .error {
                    HapticService.error()
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

    private var engineCard: some View {
        let ready = connection.status.stableDiffusion == true
        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Bilder-Engine")
                        .font(.headline)
                    Spacer()
                    Circle()
                        .fill(ready ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                    Text(ready ? "Bereit" : "Aus / startet")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text("Gleiche Stable-Diffusion-Engine f?r Bildideen und Magischen Radierer ? kein anderes Modell. Wenn der Radierer bei 96?% h?ngt: hier starten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    HapticService.open()
                    Task {
                        _ = await connection.images.prepareEngine()
                        await connection.refreshStatus(showLoading: false)
                    }
                } label: {
                    Label(
                        connection.images.isPreparingEngine
                            ? "Startet auf dem PC?"
                            : (ready ? "Engine nochmal warm halten" : "Bilder-Engine starten"),
                        systemImage: "bolt.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!connection.isOnline || connection.images.isPreparingEngine || connection.images.isGenerating)
                if !connection.images.engineStatusText.isEmpty {
                    Text(connection.images.engineStatusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

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

                TextField("Beschreibe dein Bild?", text: $draftPrompt, axis: .vertical)
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
                    ImageInspirationStrip { tip in
                        draftPrompt = tip
                        connection.images.prompt = tip
                        HapticService.selection()
                    }
                }

                if !connection.images.isGenerating {
                    imageModePicker
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
                        HapticService.rigid()
                        HapticService.send()
                        connection.images.startGenerate()
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                                .symbolEffect(.bounce, value: connection.images.isGenerating)
                            Text("Auf dem PC erstellen")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.35, green: 0.7, blue: 1),
                                            NOCOAITheme.accent,
                                            Color(red: 0.85, green: 0.4, blue: 0.95)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                        .foregroundStyle(.white)
                        .shadow(color: NOCOAITheme.glowPrimary.opacity(0.45), radius: 14)
                    }
                    .disabled(draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !connection.isOnline)
                    .opacity(draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !connection.isOnline ? 0.5 : 1)

                    Text("Du kannst die App verlassen ? du bekommst eine Mitteilung, wenn das Bild fertig ist.")
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

    private var imageModePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Modell")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(ImageGenMode.allCases) { mode in
                    Button {
                        HapticService.selection()
                        connection.images.genMode = mode
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(mode.emoji) \(mode.title)")
                                .font(.caption.weight(.bold))
                            Text(mode == .flash ? "Tempo" : (mode == .think ? "Qualität" : "Auto"))
                                .font(.caption2)
                                .opacity(0.75)
                        }
                        .foregroundStyle(connection.images.genMode == mode ? Color.white : Color.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background {
                            if connection.images.genMode == mode {
                                Capsule().fill(NOCOAITheme.accent.gradient)
                            } else {
                                Capsule().fill(.ultraThinMaterial)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Gleiche Stable-Diffusion-Engine ? Flash/Think steuern Schritte & Auflösung.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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

// MARK: - Inspiration (SF Symbol placeholders ? no generated assets)

private struct ImageInspirationItem: Identifiable {
    let id: String
    let title: String
    let prompt: String
    let symbol: String
    let colors: [Color]
}

private struct ImageInspirationStrip: View {
    var onPick: (String) -> Void
    @State private var glow = false

    private let items: [ImageInspirationItem] = [
        .init(
            id: "cine",
            title: "Cinematic",
            prompt: "Neon-Stadt bei Regen, cinematic lighting, wide shot",
            symbol: "film",
            colors: [Color(red: 0.12, green: 0.18, blue: 0.42), Color(red: 0.55, green: 0.25, blue: 0.75)]
        ),
        .init(
            id: "portrait",
            title: "Portrait",
            prompt: "Soft portrait, studio light, shallow depth of field",
            symbol: "person.crop.rectangle",
            colors: [Color(red: 0.45, green: 0.32, blue: 0.28), Color(red: 0.85, green: 0.65, blue: 0.5)]
        ),
        .init(
            id: "nature",
            title: "Nature",
            prompt: "Fantasy forest, golden hour, volumetric light",
            symbol: "leaf.fill",
            colors: [Color(red: 0.12, green: 0.38, blue: 0.28), Color(red: 0.55, green: 0.75, blue: 0.35)]
        ),
        .init(
            id: "product",
            title: "Product",
            prompt: "Minimal product shot on white, soft shadows",
            symbol: "cube.transparent",
            colors: [Color(red: 0.22, green: 0.24, blue: 0.28), Color(red: 0.55, green: 0.58, blue: 0.65)]
        ),
        .init(
            id: "abstract",
            title: "Abstract",
            prompt: "Abstract fluid shapes, soft gradients, modern art",
            symbol: "waveform",
            colors: [Color(red: 0.2, green: 0.45, blue: 0.7), Color(red: 0.9, green: 0.45, blue: 0.55)]
        ),
        .init(
            id: "arch",
            title: "Architecture",
            prompt: "Modern architecture, clean lines, dusk sky",
            symbol: "building.2.fill",
            colors: [Color(red: 0.18, green: 0.22, blue: 0.35), Color(red: 0.4, green: 0.55, blue: 0.75)]
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Inspiration")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            onPick(item.prompt)
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: item.colors,
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay(
                                        Image(systemName: item.symbol)
                                            .font(.system(size: 28, weight: .light))
                                            .foregroundStyle(.white.opacity(0.55))
                                            .offset(x: glow ? 4 : -2, y: glow ? -3 : 2)
                                    )
                                    .overlay(
                                        LinearGradient(
                                            colors: [.clear, .black.opacity(0.45)],
                                            startPoint: .center,
                                            endPoint: .bottom
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                    Text("Tippen zum ?bernehmen")
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                                .padding(10)
                            }
                            .frame(width: 132, height: 96)
                            .shadow(color: item.colors.last?.opacity(0.35) ?? .clear, radius: glow ? 10 : 4, y: 3)
                            .scaleEffect(glow ? 1.0 : 0.985)
                            .animation(
                                .easeInOut(duration: 2.2)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.12),
                                value: glow
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .onAppear { glow = true }
    }
}
