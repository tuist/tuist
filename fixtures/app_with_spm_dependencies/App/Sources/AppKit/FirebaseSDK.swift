//
//  FirebaseSDK.swift
//  AppKit
//
//  Created by Shahzad Majeed on 2/18/24.
//

import Foundation
import FirebaseCore
import FirebaseRemoteConfig

@MainActor
public final class FirebaseManager {
    private var currentConfig: RemoteConfig?
    private var configListener: ConfigUpdateListenerRegistration? = nil

    static let manager = FirebaseManager()
    
    let options: FirebaseOptions = {
        let options = FirebaseOptions(googleAppID: "1:497863470056:ios:0dfa07e158e9187cfcd25d", gcmSenderID: "497863470056")
        options.bundleID = "io.tuist.app"
        options.apiKey = "AIzaSyBHdt0eVu3VvSG6RsVDUJL5afVdfVtM3nw"
        options.projectID = "tuistdemoproject"
        return options
    }()
    
    public static func run() {
        Task(priority: .high) { @MainActor in
            await manager.initialize()
            await manager.fetchAndActivateFirebase()
            await manager.read()
        }
    }
    
    public func initialize() async {
        /// Initialize default app (for some weird reason you have to initialize default app otherwise FRC SDK logs warnings)
        FirebaseApp.configure(options: options)
        /// Initialize registered app
        FirebaseApp.configure(name: options.projectID ?? "tuistdemoproject", options: options)
        
        guard let app = FirebaseApp.app(name: options.projectID!) else {
            return assertionFailure(
                """
                Attempted to initialize FirebaseRemoteConfig with projectId \(String(describing: options.projectID))
                before any Firebase App with that Id has been configured.
                Initialize this Id with Firebase Manager first to avoid this.
                """
            )
        }
        currentConfig = RemoteConfig.remoteConfig(app: app)
    }
    
    public func fetchAndActivateFirebase() async {
        guard let currentConfig else {
            return assertionFailure(
                """
                Please make sure that RemoteConfig is initialized with `FirebaseApp` first...
                """
            )
        }
        
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 0
        currentConfig.configSettings = settings
      
        do {
            try await currentConfig.fetchAndActivate()
        } catch {
            print("Firebase Remote Config Fetch Error | error: \(String(describing: error))")
        }
        
        configListener = currentConfig.addOnConfigUpdateListener { configUpdate, error in
            if let error {
                print("Firebase.addOnConfigUpdateListener error: \(error)")
            } else {
                currentConfig.activate()
                let updatedKeys = configUpdate?.updatedKeys ?? Set()
                print("Firebase.addOnConfigUpdateListener update: \(updatedKeys)")
                Task(priority: .high) {
                    await self.read()
                }
            }
        }
    }
    
    func read() async {
        guard let config = self.currentConfig else { return }
        let value = config.configValue(forKey: "Tuist_Demo_App_Config").stringValue
        print("Tuist_Demo_App_Config: \(String(describing: value))")
    }
}
