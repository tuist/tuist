require 'cli/ui'
require 'cli/kit/ruby_backports/enumerable'

module CLI
  module Kit
    autoload :Autocall,        'cli/kit/autocall'
    autoload :BaseCommand,     'cli/kit/base_command'
    autoload :CommandRegistry, 'cli/kit/command_registry'
    autoload :Config,          'cli/kit/config'
    autoload :ErrorHandler,    'cli/kit/error_handler'
    autoload :Executor,        'cli/kit/executor'
    autoload :Ini,             'cli/kit/ini'
    autoload :Levenshtein,     'cli/kit/levenshtein'
    autoload :Logger,          'cli/kit/logger'
    autoload :Resolver,        'cli/kit/resolver'
    autoload :Support,         'cli/kit/support'
    autoload :System,          'cli/kit/system'
    autoload :Util,            'cli/kit/util'

    EXIT_FAILURE_BUT_NOT_BUG = 30
    EXIT_BUG                 = 1
    EXIT_SUCCESS             = 0

    # Abort, Bug, AbortSilent, and BugSilent are four ways of immediately bailing
    # on command-line execution when an unrecoverable error occurs.
    #
    # Note that these don't inherit from StandardError, and so are not caught by
    # a bare `rescue => e`.
    #
    # * Abort prints its message in red and exits 1;
    # * Bug additionally submits the exception to Bugsnag;
    # * AbortSilent and BugSilent do the same as above, but do not print
    #     messages before exiting.
    #
    # Treat these like panic() in Go:
    #   * Don't rescue them. Use a different Exception class if you plan to recover;
    #   * Provide a useful message, since it will be presented in brief to the
    #       user, and will be useful for debugging.
    #   * Avoid using it if it does actually make sense to recover from an error.
    #
    # Additionally:
    #   * Do not subclass these.
    #   * Only use AbortSilent or BugSilent if you prefer to print a more
    #       contextualized error than Abort or Bug would present to the user.
    #   * In general, don't attach a message to AbortSilent or BugSilent.
    #   * Never raise GenericAbort directly.
    #   * Think carefully about whether Abort or Bug is more appropriate. Is this
    #       a bug in the tool? Or is it just user error, transient network
    #       failure, etc.?
    #   * One case where it's ok to rescue (cli-kit internals or tests aside):
    #       1. rescue Abort or Bug
    #       2. Print a contextualized error message
    #       3. Re-raise AbortSilent or BugSilent respectively.
    GenericAbort = Class.new(Exception)
    Abort        = Class.new(GenericAbort)
    Bug          = Class.new(GenericAbort)
    BugSilent    = Class.new(GenericAbort)
    AbortSilent  = Class.new(GenericAbort)
  end
end
