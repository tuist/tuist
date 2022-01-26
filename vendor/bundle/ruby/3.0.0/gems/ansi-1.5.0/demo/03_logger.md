# ANSI::Logger

Require the ANSI::Logger library.

    require 'ansi/logger'

Create a new ANSI::Logger

    log = ANSI::Logger.new(STDOUT)

Info logging appears normal.

    log.info{"Info logs are green.\n"}

Warn logging appears yellow.

    log.warn{"Warn logs are yellow.\n"}

Debug logging appears cyan.

    log.debug{"Debug logs are cyan.\n"}

Error logging appears red.

    log.error{"Error logs are red.\n"}

Fatal logging appears bright red.

    log.fatal{"Fatal logs are bold red!\n"}

