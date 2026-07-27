import SwiftUI

struct BrandLogo: View {
    var size: CGFloat = 88

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .shadow(color: NOCOAITheme.accent.opacity(0.35), radius: 16, y: 8)
    }
}
