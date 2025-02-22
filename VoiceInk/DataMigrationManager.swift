import Foundation
import os

class DataMigrationManager {
    private let logger = Logger(
        subsystem: "com.prakashjoshipax.VoiceInk",
        category: "DataMigration"
    )
    
    static let shared = DataMigrationManager()
    private let swiftDataMigrationKey = "hasPerformedSwiftDataMigration"
    private let whisperModelsMigrationKey = "hasPerformedWhisperModelsMigration"
    private let preferencesMigrationKey = "hasPerformedPreferencesMigration"
    
    private init() {}
    
    func performMigrationsIfNeeded() {
        migratePreferencesIfNeeded()  // Do preferences first as other migrations might need new preferences
        migrateSwiftDataStoreIfNeeded()
        migrateWhisperModelsIfNeeded()
    }
    
    private func migratePreferencesIfNeeded() {
        // Check if migration has already been performed
        if UserDefaults.standard.bool(forKey: preferencesMigrationKey) {
            logger.info("Preferences migration already performed")
            return
        }
        
        logger.info("Starting preferences migration")
        
        let bundleId = "com.prakashjoshipax.VoiceInk"
        
        // Old location (in Containers)
        let oldPrefsURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Containers/\(bundleId)/Data/Library/Preferences/\(bundleId).plist")
        
        // New location
        let newPrefsURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Preferences/\(bundleId).plist")
        
        do {
            if FileManager.default.fileExists(atPath: oldPrefsURL.path) {
                logger.info("Found old preferences at: \(oldPrefsURL.path)")
                
                // Read old preferences
                let oldPrefsData = try Data(contentsOf: oldPrefsURL)
                if let oldPrefs = try PropertyListSerialization.propertyList(from: oldPrefsData, format: nil) as? [String: Any] {
                    
                    // Migrate each preference to new UserDefaults
                    for (key, value) in oldPrefs {
                        UserDefaults.standard.set(value, forKey: key)
                        logger.info("Migrated preference: \(key)")
                    }
                    
                    // Ensure changes are written to disk
                    UserDefaults.standard.synchronize()
                    
                    // Try to remove old preferences file
                    try? FileManager.default.removeItem(at: oldPrefsURL)
                    logger.info("Removed old preferences file")
                }
                
                // Mark migration as complete
                UserDefaults.standard.set(true, forKey: preferencesMigrationKey)
                logger.info("Preferences migration completed successfully")
            } else {
                logger.info("No old preferences file found at: \(oldPrefsURL.path)")
                // Mark migration as complete even if no old prefs found
                UserDefaults.standard.set(true, forKey: preferencesMigrationKey)
            }
        } catch {
            logger.error("Failed to migrate preferences: \(error.localizedDescription)")
        }
    }
    
    private func migrateSwiftDataStoreIfNeeded() {
        // Check if migration has already been performed
        if UserDefaults.standard.bool(forKey: swiftDataMigrationKey) {
            logger.info("SwiftData migration already performed")
            return
        }
        
        logger.info("Starting SwiftData store migration")
        
        // Old location (in Containers directory)
        let oldContainerURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .deletingLastPathComponent() // Go up to Library
            .appendingPathComponent("Containers/com.prakashjoshipax.VoiceInk/Data/Library/Application Support")
        
        // New location (in Application Support)
        let newContainerURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.prakashjoshipax.VoiceInk")
        
        let storeFiles = [
            "default.store",
            "default.store-wal",
            "default.store-shm"
        ]
        
        do {
            // Create new directory if it doesn't exist
            try FileManager.default.createDirectory(at: newContainerURL, withIntermediateDirectories: true)
            
            // Migrate each store file
            for fileName in storeFiles {
                let oldURL = oldContainerURL.appendingPathComponent(fileName)
                let newURL = newContainerURL.appendingPathComponent(fileName)
                
                if FileManager.default.fileExists(atPath: oldURL.path) {
                    logger.info("Migrating \(fileName)")
                    
                    // If a file already exists at the destination, remove it first
                    if FileManager.default.fileExists(atPath: newURL.path) {
                        try FileManager.default.removeItem(at: newURL)
                    }
                    
                    // Copy the file to new location
                    try FileManager.default.copyItem(at: oldURL, to: newURL)
                    
                    // Remove the old file
                    try FileManager.default.removeItem(at: oldURL)
                    
                    logger.info("Successfully migrated \(fileName)")
                } else {
                    logger.info("No \(fileName) found at old location")
                }
            }
            
            // Mark migration as complete
            UserDefaults.standard.set(true, forKey: swiftDataMigrationKey)
            logger.info("SwiftData migration completed successfully")
            
        } catch {
            logger.error("Failed to migrate SwiftData store: \(error.localizedDescription)")
        }
    }
    
    private func migrateWhisperModelsIfNeeded() {
        // Check if migration has already been performed
        if UserDefaults.standard.bool(forKey: whisperModelsMigrationKey) {
            logger.info("Whisper models migration already performed")
            return
        }
        
        logger.info("Starting Whisper models migration")
        
        // Old location (in Containers directory)
        let oldModelsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .deletingLastPathComponent() // Go up to Documents
            .deletingLastPathComponent() // Go up to Data
            .deletingLastPathComponent() // Go up to com.prakashjoshipax.VoiceInk
            .deletingLastPathComponent() // Go up to Containers
            .appendingPathComponent("com.prakashjoshipax.VoiceInk/Data/Documents/WhisperModels")
        
        // New location (in Documents)
        let newModelsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WhisperModels")
        
        do {
            // Create new directory if it doesn't exist
            try FileManager.default.createDirectory(at: newModelsURL, withIntermediateDirectories: true)
            
            // Get all files in the old directory
            if let modelFiles = try? FileManager.default.contentsOfDirectory(at: oldModelsURL, includingPropertiesForKeys: nil) {
                for modelURL in modelFiles {
                    let fileName = modelURL.lastPathComponent
                    let newURL = newModelsURL.appendingPathComponent(fileName)
                    
                    logger.info("Migrating model: \(fileName)")
                    
                    // If a file already exists at the destination, remove it first
                    if FileManager.default.fileExists(atPath: newURL.path) {
                        try FileManager.default.removeItem(at: newURL)
                    }
                    
                    // Copy the file to new location
                    try FileManager.default.copyItem(at: modelURL, to: newURL)
                    
                    // Remove the old file
                    try FileManager.default.removeItem(at: modelURL)
                    
                    logger.info("Successfully migrated model: \(fileName)")
                }
            }
            
            // Mark migration as complete
            UserDefaults.standard.set(true, forKey: whisperModelsMigrationKey)
            logger.info("Whisper models migration completed successfully")
            
        } catch {
            logger.error("Failed to migrate Whisper models: \(error.localizedDescription)")
        }
    }
} 