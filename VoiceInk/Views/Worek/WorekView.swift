import SwiftUI
import AppKit

// MARK: - Window Controller

@MainActor
final class WorekWindowController {
    static let shared = WorekWindowController()
    private init() {}

    private var panel: NSPanel?
    private var hostingController: NSHostingController<AnyView>?

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        if isVisible { panel?.makeKeyAndOrderFront(nil); return }

        let size = NSSize(width: 480, height: 560)
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let origin = NSPoint(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.midY - size.height / 2 + 40
        )

        let newPanel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable, .closable],
            backing: .buffered,
            defer: false
        )
        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.hidesOnDeactivate = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.isMovableByWindowBackground = true
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = true
        newPanel.titlebarAppearsTransparent = true
        newPanel.titleVisibility = .hidden
        newPanel.standardWindowButton(.closeButton)?.isHidden = true
        newPanel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        newPanel.standardWindowButton(.zoomButton)?.isHidden = true
        newPanel.minSize = NSSize(width: 360, height: 300)
        newPanel.title = "Worek"

        let view = WorekView(onClose: { [weak self] in self?.hide() })
        let controller = NSHostingController(rootView: AnyView(view))
        newPanel.contentView = controller.view
        hostingController = controller
        panel = newPanel

        newPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        hostingController = nil
    }
}

// MARK: - View

struct WorekView: View {
    let onClose: () -> Void

    @ObservedObject private var store = WorekStore.shared
    @State private var copiedID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)

            if store.entries.isEmpty {
                emptyState
            } else {
                entryList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppTheme.Border.tint, lineWidth: 0.5)
        )
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "bag")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Worek")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if !store.entries.isEmpty {
                Button {
                    store.clear()
                } label: {
                    Text("Wyczyść")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Usuń wszystkie notatki")
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bag")
                .font(.system(size: 32))
                .foregroundStyle(.quaternary)
            Text("Worek jest pusty")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("W edytorze wciśnij ⌥↵ aby zapisać notatkę")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Entry list

    private var entryList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(store.entries) { entry in
                    entryRow(entry)
                }
            }
            .padding(10)
        }
    }

    private func entryRow(_ entry: WorekEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            VStack(alignment: .trailing, spacing: 4) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.text, forType: .string)
                    copiedID = entry.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if copiedID == entry.id { copiedID = nil }
                    }
                } label: {
                    Image(systemName: copiedID == entry.id ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(copiedID == entry.id ? AppTheme.Status.success : .secondary)
                }
                .buttonStyle(.plain)
                .help("Kopiuj")

                Button {
                    store.remove(id: entry.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Usuń")

                Text(entry.createdAt, style: .time)
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.Surface.control.opacity(0.5))
        )
    }
}
