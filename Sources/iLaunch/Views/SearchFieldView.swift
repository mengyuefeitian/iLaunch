import SwiftUI

/// Launchpad-style search capsule. Uses a real layout size so it always paints
/// (no zero-height TextField quirks on borderless overlay windows).
struct SearchFieldView: View {
    @Binding var text: String
    @FocusState.Binding var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))

            ZStack(alignment: .leading) {
                // Explicit placeholder so the field is never an empty invisible strip.
                if text.isEmpty {
                    Text("Search")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .allowsHitTesting(false)
                }
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .tint(.white)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(width: 420, height: 40)
        .liquidGlassCapsule(fallbackOpacity: 0.32)
        .shadow(color: .black.opacity(0.35), radius: 10, y: 2)
        .contentShape(Capsule())
    }
}
