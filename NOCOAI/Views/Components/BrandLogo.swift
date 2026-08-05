import SwiftUI

struct BrandLogo: View {
    var size: CGFloat = 88

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.223, style: .continuous))
            .shadow(color: NOCOAITheme.glowPrimary.opacity(0.55), radius: size * 0.22, y: size * 0.06)
            .shadow(color: NOCOAITheme.glowAccent.opacity(0.25), radius: size * 0.16)
    }
}
