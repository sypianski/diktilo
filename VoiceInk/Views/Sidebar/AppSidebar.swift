import SwiftUI

struct AppSidebar: View {
    @Binding var selectedView: ViewType

    var body: some View {
        ZStack(alignment: .trailing) {
            sidebarBackground
            sidebarDivider
            sidebarContent
        }
        .frame(width: 220)
        .frame(maxHeight: .infinity)
        .onAppear {
            ViewType.assertSidebarItemsCoverAllCases()
        }
    }

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            sidebarSection(ViewType.primaryItems)
                .padding(.top, 10)

            Spacer(minLength: 16)

            sidebarSection(ViewType.secondaryItems)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sidebarBackground: some View {
        AppTheme.Surface.sidebar
            .ignoresSafeArea(.container, edges: .top)
    }

    private var sidebarDivider: some View {
        Rectangle()
            .fill(AppTheme.Border.control)
            .frame(width: 1)
            .ignoresSafeArea(.container, edges: .top)
    }

    private func sidebarSection(_ items: [ViewType]) -> some View {
        VStack(spacing: 3) {
            ForEach(items) { viewType in
                SidebarItemButton(
                    viewType: viewType,
                    isSelected: selectedView == viewType
                ) {
                    selectedView = viewType
                }
            }
        }
        .padding(.horizontal, 10)
    }
}

extension ViewType {
    var title: LocalizedStringKey {
        switch self {
        case .transcribeAudio:
            return "Transcribe"
        case .modes:
            return "Modes"
        default:
            return LocalizedStringKey(rawValue)
        }
    }

    static let primaryItems: [ViewType] = [
        .dashboard,
        .modes,
        .transcribeAudio,
        .history,
        .dictionary,
        .models,
        .audio
    ]

    static let secondaryItems: [ViewType] = [
        .settings
    ]

    static func assertSidebarItemsCoverAllCases() {
        #if DEBUG
        let sidebarItems = primaryItems + secondaryItems
        assert(Set(sidebarItems) == Set(allCases) && sidebarItems.count == allCases.count)
        #endif
    }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.medium"
        case .transcribeAudio: return "waveform.path"
        case .history: return "doc.text"
        case .models: return "cpu"
        case .modes: return "sparkles"
        case .audio: return "mic"
        case .dictionary: return "text.book.closed"
        case .settings: return "gearshape"
        }
    }
}

struct SidebarItemButton: View {
    let viewType: ViewType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: viewType.icon)
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 20)

                Text(viewType.title)
                    .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? AppTheme.Palette.onAmber : AppTheme.Text.primary)
            .padding(.horizontal, 11)
            .frame(height: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Capsule().fill(isSelected ? AppTheme.Palette.amber : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(viewType.title)
        .accessibilityLabel(viewType.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }
}
