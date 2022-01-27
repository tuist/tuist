# frozen_string_literal: true

require 'cucumber/cli/profile_loader'
require 'cucumber/formatter/ansicolor'
require 'cucumber/glue/registry_and_more'
require 'cucumber/project_initializer'
require 'cucumber/core/test/result'

module Cucumber
  module Cli
    class Options
      CUCUMBER_PUBLISH_URL = ENV['CUCUMBER_PUBLISH_URL'] || 'https://messages.cucumber.io/api/reports -X GET'
      INDENT = ' ' * 53
      BUILTIN_FORMATS = {
        'pretty'      => ['Cucumber::Formatter::Pretty',      'Prints the feature as is - in colours.'],
        'progress'    => ['Cucumber::Formatter::Progress',    'Prints one character per scenario.'],
        'rerun'       => ['Cucumber::Formatter::Rerun',       'Prints failing files with line numbers.'],
        'usage'       => ['Cucumber::Formatter::Usage',       "Prints where step definitions are used.\n" \
                                                              "#{INDENT}The slowest step definitions (with duration) are\n" \
                                                              "#{INDENT}listed first. If --dry-run is used the duration\n" \
                                                              "#{INDENT}is not shown, and step definitions are sorted by\n" \
                                                              "#{INDENT}filename instead."],
        'stepdefs'    => ['Cucumber::Formatter::Stepdefs',    "Prints All step definitions with their locations. Same as\n" \
                                                              "#{INDENT}the usage formatter, except that steps are not printed."],
        'junit'       => ['Cucumber::Formatter::Junit',       "Generates a report similar to Ant+JUnit. Use\n" \
                                                              "#{INDENT}junit,fileattribute=true to include a file attribute."],
        'json'        => ['Cucumber::Formatter::Json',        "Prints the feature as JSON.\n" \
                                                              "#{INDENT}The JSON format is in maintenance mode.\n" \
                                                              "#{INDENT}Please consider using the message formatter\n"\
                                                              "#{INDENT}with the standalone json-formatter\n" \
                                                              "#{INDENT}(https://github.com/cucumber/cucumber/tree/master/json-formatter)."],
        'message'     => ['Cucumber::Formatter::Message',     'Outputs protobuf messages'],
        'html'        => ['Cucumber::Formatter::HTML',        'Outputs HTML report'],
        'summary'     => ['Cucumber::Formatter::Summary',     'Summary output of feature and scenarios']
      }.freeze
      max = BUILTIN_FORMATS.keys.map(&:length).max
      FORMAT_HELP_MSG = [
        'Use --format rerun --out rerun.txt to write out failing',
        'features. You can rerun them with cucumber @rerun.txt.',
        'FORMAT can also be the fully qualified class name of',
        "your own custom formatter. If the class isn't loaded,",
        'Cucumber will attempt to require a file with a relative',
        'file name that is the underscore name of the class name.',
        'Example: --format Foo::BarZap -> Cucumber will look for',
        'foo/bar_zap.rb. You can place the file with this relative',
        'path underneath your features/support directory or anywhere',
        "on Ruby's LOAD_PATH, for example in a Ruby gem."
      ].freeze

      FORMAT_HELP = (BUILTIN_FORMATS.keys.sort.map do |key|
        "  #{key}#{' ' * (max - key.length)} : #{BUILTIN_FORMATS[key][1]}"
      end) + FORMAT_HELP_MSG
      PROFILE_SHORT_FLAG = '-p'.freeze
      NO_PROFILE_SHORT_FLAG = '-P'.freeze
      PROFILE_LONG_FLAG = '--profile'.freeze
      NO_PROFILE_LONG_FLAG = '--no-profile'.freeze
      FAIL_FAST_FLAG = '--fail-fast'.freeze
      RETRY_FLAG = '--retry'.freeze
      OPTIONS_WITH_ARGS = [
        '-r', '--require', '--i18n-keywords', '-f', '--format', '-o',
        '--out', '-t', '--tags', '-n', '--name', '-e', '--exclude',
        PROFILE_SHORT_FLAG, PROFILE_LONG_FLAG, RETRY_FLAG, '-l',
        '--lines', '--port', '-I', '--snippet-type'
      ].freeze
      ORDER_TYPES = %w[defined random].freeze
      TAG_LIMIT_MATCHER = /(?<tag_name>\@\w+):(?<limit>\d+)/x

      def self.parse(args, out_stream, error_stream, options = {})
        new(out_stream, error_stream, options).parse!(args)
      end

      def initialize(out_stream = STDOUT, error_stream = STDERR, options = {})
        @out_stream   = out_stream
        @error_stream = error_stream

        @default_profile = options[:default_profile]
        @profiles = options[:profiles] || []
        @overridden_paths = []
        @options = default_options.merge(options)
        @profile_loader = options[:profile_loader]
        @options[:skip_profile_information] = options[:skip_profile_information]

        @disable_profile_loading = nil
      end

      def [](key)
        @options[key]
      end

      def []=(key, value)
        @options[key] = value
      end

      def parse!(args) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        @args = args
        @expanded_args = @args.dup

        @args.extend(::OptionParser::Arguable)

        @args.options do |opts| # rubocop:disable Metrics/BlockLength
          opts.banner = banner
          opts.on('--publish', 'Publish a report to https://reports.cucumber.io') do
            set_option :publish_enabled, true
          end
          opts.on('--publish-quiet', 'Don\'t print information banner about publishing reports') { set_option :publish_quiet }
          opts.on('-r LIBRARY|DIR', '--require LIBRARY|DIR', *require_files_msg) { |lib| require_files(lib) }

          opts.on('-j DIR', '--jars DIR', 'Load all the jars under DIR') { |jars| load_jars(jars) } if Cucumber::JRUBY

          opts.on("#{RETRY_FLAG} ATTEMPTS", *retry_msg) { |v| set_option :retry, v.to_i }
          opts.on('--i18n-languages', *i18n_languages_msg) { list_languages_and_exit }
          opts.on('--i18n-keywords LANG', *i18n_keywords_msg) { |lang| language lang }
          opts.on(FAIL_FAST_FLAG, 'Exit immediately following the first failing scenario') { set_option :fail_fast }
          opts.on('-f FORMAT', '--format FORMAT', *format_msg, *FORMAT_HELP) do |v|
            add_option :formats, [*parse_formats(v), @out_stream]
          end
          opts.on('--init', *init_msg) { |_v| initialize_project }
          opts.on('-o', '--out [FILE|DIR|URL]', *out_msg) { |v| out_stream v }
          opts.on('-t TAG_EXPRESSION', '--tags TAG_EXPRESSION', *tags_msg) { |v| add_tag v }
          opts.on('-n NAME', '--name NAME', *name_msg) { |v| add_option :name_regexps, /#{v}/ }
          opts.on('-e', '--exclude PATTERN', *exclude_msg) { |v| add_option :excludes, Regexp.new(v) }
          opts.on(PROFILE_SHORT_FLAG, "#{PROFILE_LONG_FLAG} PROFILE", *profile_short_flag_msg) { |v| add_profile v }
          opts.on(NO_PROFILE_SHORT_FLAG, NO_PROFILE_LONG_FLAG, *no_profile_short_flag_msg) { |_v| disable_profile_loading }
          opts.on('-c', '--[no-]color', *color_msg) { |v| color v }
          opts.on('-d', '--dry-run', *dry_run_msg) { set_dry_run_and_duration }
          opts.on('-m', '--no-multiline', "Don't print multiline strings and tables under steps.") { set_option :no_multiline }
          opts.on('-s', '--no-source', "Don't print the file and line of the step definition with the steps.") { set_option :source, false }
          opts.on('-i', '--no-snippets', "Don't print snippets for pending steps.") { set_option :snippets, false }
          opts.on('-I', '--snippet-type TYPE', *snippet_type_msg) { |v| set_option :snippet_type, v.to_sym }
          opts.on('-q', '--quiet', 'Alias for --no-snippets --no-source --no-duration --publish-quiet.') { shut_up }
          opts.on('--no-duration', "Don't print the duration at the end of the summary") { set_option :duration, false }
          opts.on('-b', '--backtrace', 'Show full backtrace for all errors.') { Cucumber.use_full_backtrace = true }
          opts.on('-S', '--[no-]strict', *strict_msg) { |setting| set_strict(setting) }
          opts.on('--[no-]strict-undefined', 'Fail if there are any undefined results.') { |setting| set_strict(setting, :undefined) }
          opts.on('--[no-]strict-pending', 'Fail if there are any pending results.') { |setting| set_strict(setting, :pending) }
          opts.on('--[no-]strict-flaky', 'Fail if there are any flaky results.') { |setting| set_strict(setting, :flaky) }
          opts.on('-w', '--wip', 'Fail if there are any passing scenarios.') { set_option :wip }
          opts.on('-v', '--verbose', 'Show the files and features loaded.') { set_option :verbose }
          opts.on('-g', '--guess', 'Guess best match for Ambiguous steps.') { set_option :guess }
          opts.on('-l', '--lines LINES', *lines_msg) { |lines| set_option :lines, lines }
          opts.on('-x', '--expand', 'Expand Scenario Outline Tables in output.') { set_option :expand }

          opts.on('--order TYPE[:SEED]', 'Run examples in the specified order. Available types:',
                  *<<-TEXT.split("\n")) do |order|
  [defined]     Run scenarios in the order they were defined (default).
  [random]      Shuffle scenarios before running.
Specify SEED to reproduce the shuffling from a previous run.
  e.g. --order random:5738
                  TEXT
            @options[:order], @options[:seed] = *order.split(':')
            raise "'#{@options[:order]}' is not a recognised order type. Please use one of #{ORDER_TYPES.join(', ')}." unless ORDER_TYPES.include?(@options[:order])
          end

          opts.on_tail('--version', 'Show version.') { exit_ok(Cucumber::VERSION) }
          opts.on_tail('-h', '--help', "You're looking at it.") { exit_ok(opts.help) }
        end.parse!

        process_publish_options

        @args.map! { |a| "#{a}:#{@options[:lines]}" } if @options[:lines]

        extract_environment_variables
        @options[:paths] = @args.dup # whatver is left over

        check_formatter_stream_conflicts

        merge_profiles

        self
      end

      def custom_profiles
        @profiles - [@default_profile]
      end

      def filters
        @options[:filters] ||= []
      end

      def check_formatter_stream_conflicts
        streams = @options[:formats].uniq.map { |(_, _, stream)| stream }
        return if streams == streams.uniq
        raise 'All but one formatter must use --out, only one can print to each stream (or STDOUT)'
      end

      def to_hash
        Hash(@options)
      end

      protected

      attr_reader :options, :profiles, :expanded_args
      protected :options, :profiles, :expanded_args

      private

      def process_publish_options
        @options[:publish_enabled] = true if truthy_string?(ENV['CUCUMBER_PUBLISH_ENABLED']) || ENV['CUCUMBER_PUBLISH_TOKEN']
        @options[:formats] << publisher if @options[:publish_enabled]

        @options[:publish_quiet] = true if truthy_string?(ENV['CUCUMBER_PUBLISH_QUIET'])
      end

      def truthy_string?(str)
        return false if str.nil?
        str !~ /^(false|no|0)$/i
      end

      def color_msg
        [
          'Whether or not to use ANSI color in the output. Cucumber decides',
          'based on your platform and the output destination if not specified.'
        ]
      end

      def dry_run_msg
        ['Invokes formatters without executing the steps.']
      end

      def exclude_msg
        ["Don't run feature files or require ruby files matching PATTERN"]
      end

      def format_msg
        ['How to format features (Default: pretty). Available formats:']
      end

      def i18n_languages_msg
        [
          'List all available languages'
        ]
      end

      def i18n_keywords_msg
        [
          'List keywords for in a particular language',
          %(Run with "--i18n help" to see all languages)
        ]
      end

      def init_msg
        [
          'Initializes folder structure and generates conventional files for',
          'a Cucumber project.'
        ]
      end

      def lines_msg
        ['Run given line numbers. Equivalent to FILE:LINE syntax']
      end

      def no_profile_short_flag_msg
        [
          "Disables all profile loading to avoid using the 'default' profile."
        ]
      end

      def profile_short_flag_msg
        [
          'Pull commandline arguments from cucumber.yml which can be defined as',
          "strings or arrays.  When a 'default' profile is defined and no profile",
          'is specified it is always used. (Unless disabled, see -P below.)',
          'When feature files are defined in a profile and on the command line',
          'then only the ones from the command line are used.'
        ]
      end

      def retry_msg
        ['Specify the number of times to retry failing tests (default: 0)']
      end

      def name_msg
        [
          'Only execute the feature elements which match part of the given name.',
          'If this option is given more than once, it will match against all the',
          'given names.'
        ]
      end

      def strict_msg
        [
          'Fail if there are any strict affected results ',
          '(that is undefined, pending or flaky results).'
        ]
      end

      def parse_formats(v)
        formatter, *formatter_options = v.split(',')
        options_hash = Hash[formatter_options.map { |s| s.split('=') }]
        [formatter, options_hash]
      end

      def out_stream(v)
        @options[:formats] << ['pretty', {}, nil] if @options[:formats].empty?
        @options[:formats][-1][2] = v
      end

      def tags_msg
        [
          'Only execute the features or scenarios with tags matching TAG_EXPRESSION.',
          'Scenarios inherit tags declared on the Feature level. The simplest',
          'TAG_EXPRESSION is simply a tag. Example: --tags @dev. To represent',
          "boolean NOT preceed the tag with 'not '. Example: --tags 'not @dev'.",
          'A tag expression can have several tags separated by an or which represents',
          "logical OR. Example: --tags '@dev or @wip'. The --tags option can be specified",
          'A tag expression can have several tags separated by an and which represents',
          "logical AND. Example: --tags '@dev and @wip'. The --tags option can be specified",
          'several times, and this also represents logical AND.',
          "Example: --tags '@foo or not @bar' --tags @zap. This represents the boolean",
          'expression (@foo || !@bar) && @zap.',
          "\n",
          'Beware that if you want to use several negative tags to exclude several tags',
          "you have to use logical AND: --tags 'not @fixme and not @buggy'.",
          "\n",
          'Tags can be given a threshold to limit the number of occurrences.',
          'Example: --tags @qa:3 will fail if there are more than 3 occurrences of the @qa tag.',
          'This can be practical if you are practicing Kanban or CONWIP.'
        ]
      end

      def out_msg
        [
          'Write output to a file/directory/URL instead of STDOUT. This option',
          'applies to the previously specified --format, or the',
          'default format if no format is specified. Check the specific',
          "formatter's docs to see whether to pass a file, dir or URL.",
          "\n",
          'When using a URL, the output of the formatter will be sent as the HTTP request body.',
          'HTTP headers and request method can be set with cURL like options.',
          'Example: --out "http://example.com -X POST -H Content-Type:text/json"'
        ]
      end

      def require_files_msg
        [
          'Require files before executing the features. If this',
          'option is not specified, all *.rb files that are',
          'siblings of or below the features will be loaded auto-',
          'matically. Automatic loading is disabled when this',
          'option is specified; all loading becomes explicit.',
          'Files in directories named "support" are still always',
          'loaded first when their parent directories are',
          'required or if the "support" directories themselves are',
          'explicitly required.',
          'This option can be specified multiple times.'
        ]
      end

      def snippet_type_msg
        [
          'Use different snippet type (Default: cucumber_expression). Available types:',
          Cucumber::Glue::RegistryAndMore.cli_snippet_type_options
        ].flatten
      end

      def banner
        [
          'Usage: cucumber [options] [ [FILE|DIR|URL][:LINE[:LINE]*] ]+', '',
          'Examples:',
          'cucumber examples/i18n/en/features',
          'cucumber @rerun.txt (See --format rerun)',
          'cucumber examples/i18n/it/features/somma.feature:6:98:113',
          'cucumber -s -i http://rubyurl.com/eeCl', '', ''
        ].join("\n")
      end

      def require_files(v)
        @options[:require] << v
        return unless Cucumber::JRUBY && File.directory?(v)
        require 'java'
        $CLASSPATH << v
      end

      def require_jars(jars)
        Dir["#{jars}/**/*.jar"].sort.each { |jar| require jar }
      end

      def publisher
        url = CUCUMBER_PUBLISH_URL
        url += %( -H "Authorization: Bearer #{ENV['CUCUMBER_PUBLISH_TOKEN']}") if ENV['CUCUMBER_PUBLISH_TOKEN']
        ['message', {}, url]
      end

      def language(lang)
        require 'gherkin/dialect'

        return indicate_invalid_language_and_exit(lang) unless ::Gherkin::DIALECTS.key?(lang)
        list_keywords_and_exit(lang)
      end

      def disable_profile_loading
        @disable_profile_loading = true
      end

      def non_stdout_formats
        @options[:formats].reject { |_, _, output| output == @out_stream }
      end

      def add_option(option, value)
        @options[option] << value
      end

      def add_tag(value)
        raise("Found tags option '#{value}'. '~@tag' is no longer supported, use 'not @tag' instead.") if value.include?('~')
        raise("Found tags option '#{value}'. '@tag1,@tag2' is no longer supported, use '@tag or @tag2' instead.") if value.include?(',')
        @options[:tag_expressions] << value.gsub(/(@\w+)(:\d+)?/, '\1')
        add_tag_limits(value)
      end

      def add_tag_limits(value)
        value.split(/[, ]/).map { |part| TAG_LIMIT_MATCHER.match(part) }.compact.each do |matchdata|
          add_tag_limit(@options[:tag_limits], matchdata[:tag_name], matchdata[:limit].to_i)
        end
      end

      def add_tag_limit(tag_limits, tag_name, limit)
        raise "Inconsistent tag limits for #{tag_name}: #{tag_limits[tag_name]} and #{limit}" if tag_limits[tag_name] && tag_limits[tag_name] != limit
        tag_limits[tag_name] = limit
      end

      def color(color)
        Cucumber::Term::ANSIColor.coloring = color
      end

      def initialize_project
        ProjectInitializer.new.run && Kernel.exit(0)
      end

      def add_profile(p)
        @profiles << p
      end

      def set_option(option, value = nil)
        @options[option] = value.nil? ? true : value
      end

      def set_dry_run_and_duration
        @options[:dry_run] = true
        @options[:duration] = false
      end

      def exit_ok(text)
        @out_stream.puts text
        Kernel.exit(0)
      end

      def shut_up
        @options[:publish_quiet] = true
        @options[:snippets] = false
        @options[:source] = false
        @options[:duration] = false
      end

      def set_strict(setting, type = nil)
        @options[:strict].set_strict(setting, type)
      end

      def stdout_formats
        @options[:formats].select { |_, _, output| output == @out_stream }
      end

      def extract_environment_variables
        @args.delete_if do |arg|
          if arg =~ /^(\w+)=(.*)$/
            @options[:env_vars][Regexp.last_match(1)] = Regexp.last_match(2)
            true
          end
        end
      end

      def disable_profile_loading?
        @disable_profile_loading
      end

      def merge_profiles
        if @disable_profile_loading
          @out_stream.puts 'Disabling profiles...'
          return
        end

        @profiles << @default_profile if default_profile_should_be_used?

        @profiles.each do |profile|
          merge_with_profile(profile)
        end

        @options[:profiles] = @profiles
      end

      def merge_with_profile(profile)
        profile_args = profile_loader.args_from(profile)
        profile_options = Options.parse(
          profile_args, @out_stream, @error_stream,
          skip_profile_information: true,
          profile_loader: profile_loader
        )
        reverse_merge(profile_options)
      end

      def default_profile_should_be_used?
        @profiles.empty? &&
          profile_loader.cucumber_yml_defined? &&
          profile_loader.profile?(@default_profile)
      end

      def profile_loader
        @profile_loader ||= ProfileLoader.new
      end

      def reverse_merge(other_options) # rubocop:disable Metrics/AbcSize
        @options = other_options.options.merge(@options)
        @options[:require] += other_options[:require]
        @options[:excludes] += other_options[:excludes]
        @options[:name_regexps] += other_options[:name_regexps]
        @options[:tag_expressions] += other_options[:tag_expressions]
        merge_tag_limits(@options[:tag_limits], other_options[:tag_limits])
        @options[:env_vars] = other_options[:env_vars].merge(@options[:env_vars])
        if @options[:paths].empty?
          @options[:paths] = other_options[:paths]
        else
          @overridden_paths += (other_options[:paths] - @options[:paths])
        end
        @options[:source] &= other_options[:source]
        @options[:snippets] &= other_options[:snippets]
        @options[:duration] &= other_options[:duration]
        @options[:strict] = other_options[:strict].merge!(@options[:strict])
        @options[:dry_run] |= other_options[:dry_run]

        @profiles += other_options.profiles
        @expanded_args += other_options.expanded_args

        if @options[:formats].empty?
          @options[:formats] = other_options[:formats]
        else
          @options[:formats] += other_options[:formats]
          @options[:formats] = stdout_formats[0..0] + non_stdout_formats
        end

        @options[:retry] = other_options[:retry] if @options[:retry].zero?

        self
      end

      def merge_tag_limits(option_limits, other_limits)
        other_limits.each { |key, value| add_tag_limit(option_limits, key, value) }
      end

      def indicate_invalid_language_and_exit(lang)
        @out_stream.write("Invalid language '#{lang}'. Available languages are:\n")
        list_languages_and_exit
      end

      def list_keywords_and_exit(lang)
        require 'gherkin/dialect'
        language = ::Gherkin::Dialect.for(lang)
        data = Cucumber::MultilineArgument::DataTable.from(
          [
            ['feature', to_keywords_string(language.feature_keywords)],
            ['background', to_keywords_string(language.background_keywords)],
            ['scenario', to_keywords_string(language.scenario_keywords)],
            ['scenario_outline', to_keywords_string(language.scenario_outline_keywords)],
            ['examples', to_keywords_string(language.examples_keywords)],
            ['given', to_keywords_string(language.given_keywords)],
            ['when', to_keywords_string(language.when_keywords)],
            ['then', to_keywords_string(language.then_keywords)],
            ['and', to_keywords_string(language.and_keywords)],
            ['but', to_keywords_string(language.but_keywords)],
            ['given (code)', to_code_keywords_string(language.given_keywords)],
            ['when (code)', to_code_keywords_string(language.when_keywords)],
            ['then (code)', to_code_keywords_string(language.then_keywords)],
            ['and (code)', to_code_keywords_string(language.and_keywords)],
            ['but (code)', to_code_keywords_string(language.but_keywords)]
          ]
        )
        @out_stream.write(data.to_s(color: false, prefixes: Hash.new('')))
        Kernel.exit(0)
      end

      def list_languages_and_exit
        require 'gherkin/dialect'
        data = Cucumber::MultilineArgument::DataTable.from(
          ::Gherkin::DIALECTS.keys.map do |key|
            [key, ::Gherkin::DIALECTS[key].fetch('name'), ::Gherkin::DIALECTS[key].fetch('native')]
          end
        )
        @out_stream.write(data.to_s(color: false, prefixes: Hash.new('')))
        Kernel.exit(0)
      end

      def to_keywords_string(list)
        list.map { |item| "\"#{item}\"" }.join(', ')
      end

      def to_code_keywords_string(list)
        to_keywords_string(Cucumber::Gherkin::I18n.code_keywords_for(list))
      end

      def default_options
        {
          strict: Cucumber::Core::Test::Result::StrictConfiguration.new,
          require: [],
          dry_run: false,
          formats: [],
          excludes: [],
          tag_expressions: [],
          tag_limits: {},
          name_regexps: [],
          env_vars: {},
          diff_enabled: true,
          snippets: true,
          source: true,
          duration: true,
          retry: 0
        }
      end
    end
  end
end
