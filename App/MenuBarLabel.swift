import SwiftUI

struct MenuBarLabel: View {
    let count: Int

    var body: some View {
        if count == 0 {
            Image(systemName: "network")
                .opacity(0.5)
        } else {
            HStack(spacing: 3) {
                Image(systemName: "network")
                Text("\(count)")
            }
        }
    }
}
