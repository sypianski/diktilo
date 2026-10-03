import Foundation
import AppKit
import os

class ActiveWindowService: ObservableObject {
    static let shared = ActiveWindowService()
    @Published var currentApplication: NSRunningApplication?
    private let browserURLService = BrowserURLService.shared

    private let logger = Logger(
        subsystem: "cc.sypianski.diktilo",
        category: "browser.detection"
    )

    private init() {}

    @MainActor
    @discardableResult
    func beginApplyingConfiguration(
        profileId: UUID? = nil,
        shouldApply: @escaping @MainActor () -> Bool = { true }
    ) -> Task<Void, Never> {
        if let profileId = profileId,
           let config = OutputProfileManager.shared.getConfiguration(with: profileId) {
            guard shouldApply() else { return Task {} }
            OutputProfileManager.shared.setActiveConfiguration(config)
            return Task {}
        }

        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = frontmostApp.bundleIdentifier else {
            return Task {}
        }

        guard shouldApply() else { return Task {} }
        currentApplication = frontmostApp

        let quickConfig = OutputProfileManager.shared.getConfigurationForApp(bundleIdentifier)
            ?? OutputProfileManager.shared.getDefaultConfiguration()

        if let quickConfig {
            OutputProfileManager.shared.setActiveConfiguration(quickConfig)
        }

        guard let browserType = BrowserType.allCases.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return Task {}
        }

        return Task { [weak self] in
            guard let self else { return }

            do {
                let currentURL = try await self.browserURLService.getCurrentURL(from: browserType)
                await MainActor.run {
                    guard shouldApply(),
                          let config = OutputProfileManager.shared.getConfigurationForURL(currentURL) else {
                        return
                    }
                    OutputProfileManager.shared.setActiveConfiguration(config)
                }
            } catch is CancellationError {
                return
            } catch {
                self.logger.error("❌ Failed to get URL from \(browserType.displayName, privacy: .public): \(error, privacy: .public)")
            }
        }
    }

    func applyConfiguration(profileId: UUID? = nil) async {
        let task = await MainActor.run {
            beginApplyingConfiguration(profileId: profileId)
        }
        await task.value
    }
} 
