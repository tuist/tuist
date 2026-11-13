import Testing
import TuistLogging
@testable import TuistGenerateCommand

struct GenerateQuietHelpTests {
    @Test func generation_help_mentions_quiet() {
        #expect(GenerateCommand.helpMessage().contains("--quiet"))
        #expect(GenerateRunCommand.helpMessage().contains("--quiet"))
    }

    @Test func quiet_generation_filters_progress_without_changing_the_original_logger() {
        var logger = Logger(label: "test")
        logger.logLevel = .notice

        let quietLogger = GenerateRunCommand.generationLogger(logger, isQuiet: true)
        let normalLogger = GenerateRunCommand.generationLogger(logger, isQuiet: false)

        #expect(quietLogger.logLevel == .warning)
        #expect(normalLogger.logLevel == .notice)
        #expect(logger.logLevel == .notice)

        logger.logLevel = .error
        #expect(GenerateRunCommand.generationLogger(logger, isQuiet: true).logLevel == .error)
    }
}
