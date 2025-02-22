import Foundation
import AppKit

@MainActor
class LicenseViewModel: ObservableObject {
    enum LicenseState: Equatable {
        case trial(daysRemaining: Int)
        case trialExpired
        case licensed
    }
    
    @Published private(set) var licenseState: LicenseState = .trial(daysRemaining: 7)  // Default to trial
    @Published var licenseKey: String = ""
    @Published var isValidating = false
    @Published var validationMessage: String?
    
    private let trialPeriodDays = 7
    private let polarService = PolarService()
    private let userDefaults = UserDefaults.standard
    
    init() {
        checkLicenseState()
    }
    
    func startTrial() {
        // Only set trial start date if it hasn't been set before
        if userDefaults.trialStartDate == nil {
            userDefaults.trialStartDate = Date()
            licenseState = .trial(daysRemaining: trialPeriodDays)
            NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
        }
    }
    
    private func checkLicenseState() {
        // Check for existing license key
        if let licenseKey = userDefaults.licenseKey {
            self.licenseKey = licenseKey
            licenseState = .licensed
            return
        }
        
        // Check if this is first launch
        let hasLaunchedBefore = userDefaults.bool(forKey: "VoiceInkHasLaunchedBefore")
        if !hasLaunchedBefore {
            // First launch - start trial automatically
            userDefaults.set(true, forKey: "VoiceInkHasLaunchedBefore")
            startTrial()
            return
        }
        
        // Only check trial if not licensed and not first launch
        if let trialStartDate = userDefaults.trialStartDate {
            let daysSinceTrialStart = Calendar.current.dateComponents([.day], from: trialStartDate, to: Date()).day ?? 0
            
            if daysSinceTrialStart >= trialPeriodDays {
                licenseState = .trialExpired
            } else {
                licenseState = .trial(daysRemaining: trialPeriodDays - daysSinceTrialStart)
            }
        } else {
            // No trial has been started yet - start it now
            startTrial()
        }
    }
    
    var canUseApp: Bool {
        switch licenseState {
        case .licensed, .trial:
            return true
        case .trialExpired:
            return false
        }
    }
    
    func openPurchaseLink() {
        if let url = URL(string: "https://tryvoiceink.com/buy") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func validateLicense() async {
        guard !licenseKey.isEmpty else {
            validationMessage = "Please enter a license key"
            return
        }
        
        isValidating = true
        
        do {
            let isValid = try await polarService.validateLicenseKey(licenseKey)
            if isValid {
                userDefaults.licenseKey = licenseKey
                licenseState = .licensed
                validationMessage = "License activated successfully!"
                NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
            } else {
                validationMessage = "Invalid license key"
            }
        } catch {
            validationMessage = "Error validating license"
        }
        
        isValidating = false
    }
    
    func removeLicense() {
        // Remove both license key and trial data
        userDefaults.licenseKey = nil
        userDefaults.trialStartDate = nil
        userDefaults.set(false, forKey: "VoiceInkHasLaunchedBefore")  // Allow trial to restart
        
        licenseState = .trial(daysRemaining: trialPeriodDays)  // Reset to trial state
        licenseKey = ""
        validationMessage = nil
        NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
        checkLicenseState()
    }
}

extension Notification.Name {
    static let licenseStatusChanged = Notification.Name("licenseStatusChanged")
}
