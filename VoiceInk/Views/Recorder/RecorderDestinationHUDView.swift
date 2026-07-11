import SwiftUI

// MARK: - RecorderDestinationHUDView
//
// A compact one-line hint bar that shows "icon  ⌥C" chips for every
// active finish-destination shortcut.  Displayed during recording so the
// user does not have to memorise the bindings.
//
// Design constraints:
//   • Matches the dark translucent aesthetic of the recorder panels.
//   • Chip = small SF-symbol icon + shortcut string in a muted capsule.
//   • Max 6 items; if fewer → centred row; if more → horizontal scroll.
//   • Visibility gated by @AppStorage "RecorderDestinationHUDEnabled".
//   • Updates reactively when shortcuts or targets change.

struct RecorderDestinationHUDView: View {
    // Observe SaveTargetManager so the view rebuilds when targets change.
    @ObservedObject private var targetManager = SaveTargetManager.shared

    // Rebuilt via .onReceive(shortcutDidChange) — see body.
    @State private var items: [FinishDestinationBindings.HUDItem] = []

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyView()
            } else {
                chipRow
            }
        }
        .onAppear { rebuildItems() }
        .onReceive(NotificationCenter.default.publisher(for: ShortcutStore.shortcutDidChange)) { _ in
            rebuildItems()
        }
        // Also rebuild when the published targets array changes (new target
        // added or removed between sessions).
        .onChange(of: targetManager.targets) {
            rebuildItems()
        }
    }

    // MARK: - Chip row

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items) { item in
                    DestinationChip(item: item)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        // Cap height so the row never grows unexpectedly.
        .frame(height: 28)
    }

    // MARK: - Rebuild helper

    @MainActor
    private func rebuildItems() {
        items = FinishDestinationBindings.hudItems()
    }
}

// MARK: - Single chip

private struct DestinationChip: View {
    let item: FinishDestinationBindings.HUDItem

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: item.icon)
                .font(.system(size: 9, weight: .regular))
                .foregroundColor(.white.opacity(0.55))

            Text(item.shortcutDisplay)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.70))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.10))
        .clipShape(Capsule())
        .help("\(item.label): \(item.shortcutDisplay)")
    }
}
