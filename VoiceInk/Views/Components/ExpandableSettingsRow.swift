import SwiftUI

struct ExpandableSettingsRow<Content: View>: View {
    @Binding private var isExpanded: Bool

    private let isEnabled: Binding<Bool>?
    private let label: LocalizedStringKey
    private let infoMessage: LocalizedStringKey?
    private let infoURL: String?
    private let summary: LocalizedStringKey?
    private let statusNote: LocalizedStringKey?
    private let expandedContentTransition: AnyTransition
    private let content: () -> Content

    @State private var isHandlingToggleChange = false

    init(
        isExpanded: Binding<Bool>,
        isEnabled: Binding<Bool>,
        label: LocalizedStringKey,
        infoMessage: LocalizedStringKey? = nil,
        infoURL: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        _isExpanded = isExpanded
        self.isEnabled = isEnabled
        self.label = label
        self.infoMessage = infoMessage
        self.infoURL = infoURL
        self.summary = nil
        self.statusNote = nil
        self.expandedContentTransition = .opacity.combined(with: .move(edge: .top))
        self.content = content
    }

    /// Variant with a one-line summary and a state note under the title.
    /// `isEnabled == nil` makes a plain collapsible row.
    init(
        title: LocalizedStringKey,
        isExpanded: Binding<Bool>,
        isEnabled: Binding<Bool>?,
        summary: LocalizedStringKey,
        statusNote: LocalizedStringKey?,
        infoMessage: LocalizedStringKey? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        _isExpanded = isExpanded
        self.isEnabled = isEnabled
        self.label = title
        self.infoMessage = infoMessage
        self.infoURL = nil
        self.summary = summary
        self.statusNote = statusNote
        self.expandedContentTransition = isEnabled == nil
            ? .opacity
            : .opacity.combined(with: .move(edge: .top))
        self.content = content
    }

    init(
        title: LocalizedStringKey,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        _isExpanded = isExpanded
        self.isEnabled = nil
        self.label = title
        self.infoMessage = nil
        self.infoURL = nil
        self.summary = nil
        self.statusNote = nil
        self.expandedContentTransition = .opacity
        self.content = content
    }

    private var rowIsEnabled: Bool {
        isEnabled?.wrappedValue ?? true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let isEnabled = isEnabled {
                    Toggle(isOn: isEnabled) {
                        labelView
                    }
                } else {
                    labelView
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(rowIsEnabled && isExpanded ? 90 : 0))
                    .opacity(rowIsEnabled ? 1 : 0.4)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isHandlingToggleChange, rowIsEnabled else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }

            if rowIsEnabled && isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    content()
                }
                .padding(.top, 12)
                .padding(.leading, 4)
                .transition(expandedContentTransition)
            }
        }
        .onChange(of: rowIsEnabled) { _, newValue in
            guard isEnabled != nil else { return }
            isHandlingToggleChange = true
            if newValue {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = true
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = false
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isHandlingToggleChange = false
            }
        }
    }

    private var labelView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(label)
                if let infoMessage = infoMessage {
                    if let infoURL = infoURL {
                        InfoTip(infoMessage, learnMoreURL: infoURL)
                    } else {
                        InfoTip(infoMessage)
                    }
                }
            }
            if let summary = summary {
                Text(summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let statusNote = statusNote {
                Text(statusNote)
                    .font(.caption)
                    .foregroundColor(AppTheme.Palette.amberInk)
            }
        }
    }
}
