import SwiftUI

/// Lightweight circular mark used by Watch UI / future complications.
struct NOCOComplicationCircular: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    AngularGradient(colors: WatchRainbow.flow, center: .center),
                    lineWidth: 3
                )
            Text("N")
                .font(.caption.weight(.black))
        }
    }
}
