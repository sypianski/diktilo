import SwiftUI

struct DiagnosticsSettingsView: View {
    @State private var isExportingLogs = false
    @State private var exportedLogURL: URL?
    @State private var showLogExportError = false
    @State private var logExportError: String = ""
    @State private var isSystemInfoCopied = false

    var body: some View {
        // For bug reports: macOS, chip, model and settings summary, plus the logs.
        LabeledContent {
            HStack(spacing: 8) {
                Button(isSystemInfoCopied ? LocalizedStringKey("Copied!") : LocalizedStringKey("Copy Info")) {
                    SystemInfoService.shared.copySystemInfoToClipboard()
                    isSystemInfoCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        isSystemInfoCopied = false
                    }
                }

                if let url = exportedLogURL {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppTheme.Status.positive)
                }

                Button {
                    exportDiagnosticLogs()
                } label: {
                    HStack(spacing: 4) {
                        if isExportingLogs {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Export Logs")
                    }
                }
                .disabled(isExportingLogs)
            }
        } label: {
            Text("Bug Report")
            Text("Copy the system info and export the logs to attach to a report.")
        }
        .alert("Export Failed", isPresented: $showLogExportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(logExportError)
        }
    }

    private func exportDiagnosticLogs() {
        isExportingLogs = true
        exportedLogURL = nil

        Task {
            do {
                let url = try await LogExporter.shared.exportLogs()
                await MainActor.run {
                    exportedLogURL = url
                    isExportingLogs = false
                }
            } catch {
                await MainActor.run {
                    logExportError = error.localizedDescription
                    showLogExportError = true
                    isExportingLogs = false
                }
            }
        }
    }
}
