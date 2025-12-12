//
//  AppApp.swift
//  App
//
//  Created by Marek Fořt on 12.12.25.
//

import SwiftUI
import TuistSDK

@main
struct AppApp: App {
    private let tuistSDK = TuistSDK(
        fullHandle: "tuist/tuist",
        apiKey: "tuist_019b1324-c2f9-7f74-a467-2e0f6167099b_xE47CuzS/s4I5iEkdwnca9RKCwo=",
        serverURL: URL(string: "http://localhost:8080")!
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    tuistSDK.startUpdateChecking()
                }
        }
    }
}
