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
    @ObservedObject private var messageCenter = RecorderStatusMessageCenter.shared

    // Rebuilt via .onReceive(shortcutDidChange) — see body.
    @State private var items: [FinishDestinationBindings.HUDItem] = []

    var body: some View {
        // ZStack, not Group: modifiers on a Group are applied to its children,
        // so with no message and no chips yet there was nothing for onAppear to
        // attach to — items were never built and the band stayed empty.
        ZStack {
            if let msg = messageCenter.current {
                // Status message takes over the strip, crossfading with chips.
                HStack {
                    Spacer(minLength: 0)
                    RecorderStatusMessageView(message: msg)
                    Spacer(minLength: 0)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if !items.isEmpty {
                chipRow
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.22), value: messageCenter.current)
        .frame(height: RecorderHUDMetrics.bandHeight)
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
            // Fill the band so the chips sit vertically centred in it.
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Rebuild helper

    @MainActor
    private func rebuildItems() {
        items = FinishDestinationBindings.hudItems()
    }
}

// MARK: - Single chip

struct DestinationChip: View {
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
