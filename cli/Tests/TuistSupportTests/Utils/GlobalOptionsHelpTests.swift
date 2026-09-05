import Testing
@testable import TuistSupport

struct GlobalOptionsHelpTests {
    @Test func isHelpRequest_whenLongFlagIsPresent() {
        #expect(GlobalOptionsHelp.isHelpRequest(arguments: ["tuist", "hash", "cache", "--help"]))
    }

    @Test func isHelpRequest_whenShortFlagIsPresent() {
        #expect(GlobalOptionsHelp.isHelpRequest(arguments: ["tuist", "hash", "cache", "-h"]))
    }

    @Test func isHelpRequest_whenHelpSubcommandIsUsed() {
        #expect(GlobalOptionsHelp.isHelpRequest(arguments: ["tuist", "help", "hash", "cache"]))
    }

    @Test func isNotHelpRequest_forDumpHelp() {
        #expect(!GlobalOptionsHelp.isHelpRequest(arguments: ["tuist", "--experimental-dump-help"]))
    }

    @Test func isNotHelpRequest_forACommandNamedHelpFurtherDown() {
        #expect(!GlobalOptionsHelp.isHelpRequest(arguments: ["tuist", "generate", "help"]))
    }

    @Test func section_alignsAbstractsWithArgumentParsersLabelColumn() {
        let section = GlobalOptionsHelp.section(screenWidth: 100)

        #expect(section == """
        GLOBAL OPTIONS:
          --verbose               Display verbose logs, including the debug information commands emit.
          --quiet                 Silence all the output except errors.
        """)
    }

    @Test func section_wrapsAbstractsOntoTheLabelColumn() {
        let section = GlobalOptionsHelp.section(screenWidth: 60)

        #expect(section == """
        GLOBAL OPTIONS:
          --verbose               Display verbose logs, including
                                  the debug information commands
                                  emit.
          --quiet                 Silence all the output except
                                  errors.
        """)
    }

    @Test func appending_separatesTheSectionFromTheHelpScreen() {
        let helpText = "OPTIONS:\n  -h, --help              Show help information.\n"

        let result = GlobalOptionsHelp.appending(to: helpText, screenWidth: 100)

        #expect(result == """
        OPTIONS:
          -h, --help              Show help information.

        GLOBAL OPTIONS:
          --verbose               Display verbose logs, including the debug information commands emit.
          --quiet                 Silence all the output except errors.

        """)
    }

    @Test func screenWidth_prefersTheColumnsEnvironmentVariable() {
        #expect(GlobalOptionsHelp.screenWidth(environment: ["COLUMNS": "123"]) == 123)
    }

    @Test func screenWidth_ignoresAnInvalidColumnsEnvironmentVariable() {
        #expect(GlobalOptionsHelp.screenWidth(environment: ["COLUMNS": "0"]) != 0)
    }
}
