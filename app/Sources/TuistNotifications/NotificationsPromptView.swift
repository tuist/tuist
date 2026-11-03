import SwiftUI
import TuistAppStorage
import TuistErrorHandling
import TuistNoora

enum NotificationsPromptDismissedKey: AppStorageKey {
    static let key = "notificationsPromptDismissed"
    static let defaultValue = false
}

/// An in-context, dismissible prompt that turns on notifications on this device, asking for the permission first.
public struct NotificationsPromptView: View {
    @EnvironmentObject private var errorHandling: ErrorHandling
    private let pushNotifications: PushNotifications
    private let appStorage: AppStoring
    @State private var isDismissed: Bool

    public init() {
        self.init(pushNotifications: .shared, appStorage: AppStorage())
    }

    init(pushNotifications: PushNotifications, appStorage: AppStoring) {
        self.pushNotifications = pushNotifications
        self.appStorage = appStorage
        _isDismissed = State(initialValue: (try? appStorage.get(NotificationsPromptDismissedKey.self)) ?? false)
    }

    public var body: some View {
        if pushNotifications.permission == .notDetermined, !isDismissed {
            HStack(alignment: .top, spacing: Noora.Spacing.spacing4) {
                Image(systemName: "bell.badge")
                    .font(.title3)
                    .foregroundStyle(Noora.Colors.accent)
                VStack(alignment: .leading, spacing: Noora.Spacing.spacing2) {
                    Text("Get notified when new previews are out")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Noora.Colors.surfaceLabelPrimary)
                    Button("Turn on notifications") {
                        errorHandling.fireAndHandleError {
                            try await pushNotifications.setEnabledOnThisDevice(true)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(Noora.Colors.accent)
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                Button {
                    try? appStorage.set(NotificationsPromptDismissedKey.self, value: true)
                    withAnimation { isDismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Noora.Colors.surfaceLabelTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(Noora.Spacing.spacing5)
            .background(Noora.Colors.surfaceBackgroundTertiary, in: RoundedRectangle(cornerRadius: Noora.CornerRadius.xlarge))
            .overlay(
                RoundedRectangle(cornerRadius: Noora.CornerRadius.xlarge)
                    .strokeBorder(Noora.Colors.neutralGray24Alpha, lineWidth: 0.5)
            )
        }
    }
}
