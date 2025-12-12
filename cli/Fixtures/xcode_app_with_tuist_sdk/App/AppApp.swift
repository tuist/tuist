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
        apiKey: "tuist_019b139f-10ab-73c4-8845-4e230fe8ab8b_jC5U8ok8DvT6GhUta901ljUTUVE=",
        serverURL: URL(string: "https://staging.tuist.dev")!
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
