import SwiftUI

struct MenuBarLabel: View {
    let count: Int

    var body: some View {
        icon.modifier(CaptureOpenSettings())
    }

    @ViewBuilder
    private var icon: some View {
        if count == 0 {
            Image("MenuBarIcon")
                .opacity(0.5)
        } else {
            HStack(spacing: 3) {
                Image("MenuBarIcon")
                Text("\(count)")
            }
        }
    }
}
