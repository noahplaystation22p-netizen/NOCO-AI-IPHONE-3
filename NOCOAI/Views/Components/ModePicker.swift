import SwiftUI

/// Premium mode selection — animated identity cards, not a flat button row.
struct ModePicker: View {
    @Binding var mode: AIMode
    var recommendation: (mode: AIMode, reason: String)? = nil
    var onSelect: ((AIMode) -> Void)? = nil
    var onDismissRecommendation: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !ModeIntelligence.favoriteModes().isEmpty || !ModeIntelligence.recentModes().isEmpty {
                quickRow
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(AIMode.premiumCases) { m in
                        modeCard(m)
                    }
                }
                .padding(.vertical, 2)
            }

            if let rec = recommendation, rec.mode != mode {
                ModeRecommendationChip(
                    mode: rec.mode,
                    reason: rec.reason,
                    onApply: { select(rec.mode) },
                    onDismiss: {
                        if let onDismissRecommendation {
                            onDismissRecommendation()
                        } else {
                            onSelect?(mode)
                        }
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .intelligenceSelectionFeedback(mode)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: mode)
        .animation(.spring(response: 0.4, dampingFraction: 0.84), value: recommendation?.mode)
    }

    private var quickRow: some View {
        HStack(spacing: 8) {
            ForEach(quickModes) { m in
                Button {
                    select(m)
                } label: {
                    Image(systemName: m.systemImage)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(mode == m ? .white : m.accentColor)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle().fill(mode == m ? m.accentColor.opacity(0.9) : m.accentColor.opacity(0.12))
                        )
                }
                .buttonStyle(IntelligencePressStyle(haptic: { HapticService.selection() }))
                .accessibilityLabel(m.label)
            }
            Spacer(minLength: 0)
            Text(mode.modelHint)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(mode.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(mode.accentColor.opacity(0.12), in: Capsule())
        }
    }

    private var quickModes: [AIMode] {
        var list: [AIMode] = []
        for m in ModeIntelligence.favoriteModes() where !list.contains(m) { list.append(m) }
        for m in ModeIntelligence.recentModes() where !list.contains(m) { list.append(m) }
        return Array(list.prefix(5))
    }

    private func modeCard(_ m: AIMode) -> some View {
        let selected = mode == m
        return Button {
            select(m)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ModeIdentityGlyph(mode: m, size: 30, active: selected)
                    Spacer(minLength: 0)
                    if ModeIntelligence.isFavorite(m) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(m.accentColor)
                    }
                }

                Text(m.label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                Text(m.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(m.preview)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .frame(height: 28, alignment: .topLeading)
            }
            .padding(12)
            .frame(width: 152, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                selected
                                    ? LinearGradient(colors: [m.accentColor, m.accentColor.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : LinearGradient(colors: [Color.primary.opacity(0.08), Color.primary.opacity(0.04)], startPoint: .top, endPoint: .bottom),
                                lineWidth: selected ? 1.4 : 1
                            )
                    )
                    .shadow(color: selected ? m.accentColor.opacity(0.35) : .clear, radius: 12, y: 4)
            }
            .scaleEffect(selected ? 1.02 : 1)
        }
        .buttonStyle(IntelligencePressStyle(haptic: { HapticService.modeChange() }))
        .contextMenu {
            Button {
                ModeIntelligence.toggleFavorite(m)
                HapticService.soft()
            } label: {
                Label(
                    ModeIntelligence.isFavorite(m) ? "Favorit entfernen" : "Als Favorit",
                    systemImage: ModeIntelligence.isFavorite(m) ? "star.slash" : "star"
                )
            }
        }
        .accessibilityLabel("\(m.label), \(m.subtitle)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func select(_ m: AIMode) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
            mode = m
        }
        ModeIntelligence.recordUse(m)
        onSelect?(m)
        HapticService.modeChange()
    }
}
