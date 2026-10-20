import CrashReporting

public enum Analytics {
    public static var isCrashReportingEnabled: Bool {
        crash_reporting_enabled() == 1
    }
}
