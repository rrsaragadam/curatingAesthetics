import SwiftUI

/// "Not for me", with a reason. What you turn down is remembered, so the
/// stylist's later suggestions steer around it.
struct DeclineMenu: View {
    let onDecline: (DeclineReason) -> Void

    var body: some View {
        Menu {
            ForEach(DeclineReason.allCases) { reason in
                Button(reason.label) { onDecline(reason) }
            }
        } label: {
            Label("Not for me", systemImage: "hand.thumbsdown")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Theme.inkSecondary)
    }
}
