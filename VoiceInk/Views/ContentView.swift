import SwiftUI
import OSLog

enum ViewType: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case modes = "Modes"
    case models = "AI Models"
    case transcribeAudio = "Transcribe Audio"
    case history = "History"
    case audio = "Audio"
    case dictionary = "Dictionary"
    case settings = "Settings"

    var id: String { rawValue }
}

struct ContentView: View {
    private let logger = Logger(subsystem: "cc.sypianski.diktilo", category: "ContentView")
    @State private var selectedView: ViewType = .dashboard
    @AppStorage(AppTour.hasSeenKey) private var hasSeenTour = false
    @State private var isTourPresented = false

    var body: some View {
        HStack(spacing: 0) {
            AppSidebar(selectedView: $selectedView)

            detailContent
        }
        .frame(width: AppWindowLayout.width)
        .frame(minHeight: AppWindowLayout.minimumHeight)
        .onAppear {
            logger.notice("ContentView appeared")
            if !hasSeenTour {
                // Let the window settle before the sheet slides in.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    isTourPresented = true
                }
            }
        }
        .onDisappear {
            logger.notice("ContentView disappeared")
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToDestination)) { notification in
            if let destination = notification.userInfo?["destination"] as? String,
               let viewType = ViewType.allCases.first(where: { $0.rawValue == destination }) {
                logger.notice("navigateToDestination received: \(destination, privacy: .public)")
                selectedView = viewType
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppTour.showRequested)) { _ in
            isTourPresented = true
        }
        .sheet(isPresented: $isTourPresented, onDismiss: { hasSeenTour = true }) {
            AppTourView { isTourPresented = false }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        detailView(for: selectedView)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(detailBackground)
    }

    private var detailBackground: some View {
        AppTheme.Surface.window
            .ignoresSafeArea(.container, edges: .top)
    }
    
    @ViewBuilder
    private func detailView(for viewType: ViewType) -> some View {
        switch viewType {
        case .dashboard:
            DashboardView()
        case .models:
            ModelManagementView()
        case .transcribeAudio:
            AudioTranscribeView()
        case .history:
            InlineHistoryView()
        case .audio:
            AudioSetupView()
        case .dictionary:
            DictionarySettingsView()
        case .modes:
            OutputProfileView()
        case .settings:
            SettingsView()
        }
    }
}
