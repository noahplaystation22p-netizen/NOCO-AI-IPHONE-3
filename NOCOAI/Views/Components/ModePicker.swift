import SwiftUI

struct ModePicker: View {
    @Binding var mode: AIMode

    var body: some View {
        Picker("Modus", selection: $mode) {
            ForEach(AIMode.allCases) { m in
                Text(m.label).tag(m)
            }
        }
        .pickerStyle(.segmented)
    }
}
