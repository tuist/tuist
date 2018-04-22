import Foundation
import Sparkle

class SPUCommandLineUserDriver: NSObject, SPUUserDriver {
    let coreComponent = SPUUserDriverCoreComponent()

    // MARK: - SPUUserDriver

    func showCanCheck(forUpdates canCheckForUpdates: Bool) {
        DispatchQueue.main.async {
            self.coreComponent.showCanCheck(forUpdates: canCheckForUpdates)
        }
    }

    func show(_: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        DispatchQueue.main.async {
            let response = SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false)!
            reply(response)
        }
    }

    func showUserInitiatedUpdateCheck(completion updateCheckStatusCompletion: @escaping (SPUUserInitiatedCheckStatus) -> Void) {
        DispatchQueue.main.async {
            self.coreComponent.registerUpdateCheckStatusHandler(updateCheckStatusCompletion)
            print("Checking for updates...")
        }
    }

    func dismissUserInitiatedUpdateCheck() {
        DispatchQueue.main.async {
            self.coreComponent.completeUpdateCheckStatus()
        }
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, userInitiated _: Bool, reply: @escaping (SPUUpdateAlertChoice) -> Void) {
        DispatchQueue.main.async {
            self.showUpdate(appcastItem: appcastItem, updateAdjective: "new")
            reply(.installUpdateChoice)
        }
    }

    func showDownloadedUpdateFound(with appcastItem: SUAppcastItem, userInitiated _: Bool, reply: @escaping (SPUUpdateAlertChoice) -> Void) {
        DispatchQueue.main.async {
            self.showUpdate(appcastItem: appcastItem, updateAdjective: "downloaded")
            reply(.installUpdateChoice)
        }
    }

    func showResumableUpdateFound(with appcastItem: SUAppcastItem, userInitiated _: Bool, reply: @escaping (SPUInstallUpdateStatus) -> Void) {
        DispatchQueue.main.async {
            self.coreComponent.registerInstallUpdateHandler(reply)
            self.showUpdate(appcastItem: appcastItem, updateAdjective: "resumable")
            self.coreComponent.installUpdate(withChoice: .installUpdateNow)
        }
    }

    func showInformationalUpdateFound(with appcastItem: SUAppcastItem, userInitiated _: Bool, reply: @escaping (SPUInformationalUpdateAlertChoice) -> Void) {
        DispatchQueue.main.async {
            print("Found information for new update: %s", appcastItem.infoURL.absoluteString.utf8)
            reply(.dismissInformationalNoticeChoice)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        DispatchQueue.main.async {
            var text: Any = ""
            if downloadData.mimeType != nil && downloadData.mimeType == "text/plain" {
                text = String(data: downloadData.data, encoding: .utf8) ?? ""
                self.display(releaseNotes: text)
            } else {
                self.display(htmlReleaseNotes: downloadData.data)
            }
        }
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        DispatchQueue.main.async {
            print("Error: Unable to download release notes: %s", error.localizedDescription.utf8)
        }
    }

    func showUpdateNotFound(acknowledgement _: @escaping () -> Void) {
        DispatchQueue.main.async {
            print("No new update available!")
            exit(EXIT_SUCCESS)
        }
    }

    func showUpdaterError(_ error: Error, acknowledgement _: @escaping () -> Void) {
        DispatchQueue.main.async {
            print("Error: Update has failed: %s", error.localizedDescription.utf8)
            exit(EXIT_FAILURE)
        }
    }

    func showDownloadInitiated(completion downloadUpdateStatusCompletion: @escaping (SPUDownloadUpdateStatus) -> Void) {
        DispatchQueue.main.async {
            self.coreComponent.registerDownloadStatusHandler(downloadUpdateStatusCompletion)
            print("Downloading Update...")
        }
    }

    func showDownloadDidReceiveExpectedContentLength(_: UInt64) {
        // Do nothing
    }

    func showDownloadDidReceiveData(ofLength _: UInt64) {
        // Do nothing
    }

    func showDownloadDidStartExtractingUpdate() {
        DispatchQueue.main.async {
            self.coreComponent.completeDownloadStatus()
            print("Extracting update...")
        }
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        DispatchQueue.main.async {
            print("Extracting Update (%.0f%%)", progress * 100)
        }
    }

    func showReady(toInstallAndRelaunch installUpdateHandler: @escaping (SPUInstallUpdateStatus) -> Void) {
        DispatchQueue.main.async {
            self.coreComponent.registerInstallUpdateHandler(installUpdateHandler)
            self.coreComponent.installUpdate(withChoice: .installUpdateNow)
        }
    }

    func showInstallingUpdate() {
        DispatchQueue.main.async {
            print("Installing update...")
        }
    }

    func showSendingTerminationSignal() {
        // We are already showing that the update is installing, so there is no need to do anything here
    }

    func showUpdateInstallationDidFinish(acknowledgement: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.coreComponent.registerAcknowledgement(acknowledgement)
            print("Installation finished.")
            self.coreComponent.acceptAcknowledgement()
        }
    }

    func dismissUpdateInstallation() {
        DispatchQueue.main.async {
            print("Exiting.")
            exit(0)
        }
    }

    // MARK: - Private

    private func showUpdate(appcastItem: SUAppcastItem, updateAdjective: String) {
        print("Found (%s) update! (%s)", updateAdjective, appcastItem.displayVersionString.utf8)
        if appcastItem.itemDescription != nil {
            let data = appcastItem.itemDescription.data(using: .utf8) ?? Data()
            display(htmlReleaseNotes: data)
        }
    }

    private func display(htmlReleaseNotes: Data) {
        let text: Any = NSAttributedString(html: htmlReleaseNotes, options: [:], documentAttributes: nil)?.string.utf8 ?? ""
        display(releaseNotes: text)
    }

    private func display(releaseNotes: Any) {
        print("Release notes:")
        print("%s", releaseNotes)
    }
}

// MARK: - SPUUpdater Extension

private var _commandlineUpdater: SPUUpdater!

extension SPUUpdater {
    static func commandLine() throws -> SPUUpdater {
        if _commandlineUpdater != nil { return _commandlineUpdater }
        let driver = SPUCommandLineUserDriver()
        let bundle = try Bundle.app()
        _commandlineUpdater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: nil)
        return _commandlineUpdater
    }
}
