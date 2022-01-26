# frozen_string_literal: true

require 'cucumber/platform'
require 'cucumber/gherkin/formatter/ansi_escapes'
begin
  # Support Rake > 0.8.7
  require 'rake/dsl_definition'
rescue LoadError
end

module Cucumber
  module Rake
    # Defines a Rake task for running features.
    #
    # The simplest use of it goes something like:
    #
    #   Cucumber::Rake::Task.new
    #
    # This will define a task named <tt>cucumber</tt> described as 'Run Cucumber features'.
    # It will use steps from 'features/**/*.rb' and features in 'features/**/*.feature'.
    #
    # To further configure the task, you can pass a block:
    #
    #   Cucumber::Rake::Task.new do |t|
    #     t.cucumber_opts = %w{--format progress}
    #   end
    #
    # See the attributes for additional configuration possibilities.
    class Task
      include Cucumber::Gherkin::Formatter::AnsiEscapes
      include ::Rake::DSL if defined?(::Rake::DSL)

      class InProcessCucumberRunner #:nodoc:
        include ::Rake::DSL if defined?(::Rake::DSL)

        attr_reader :args

        def initialize(libs, cucumber_opts, feature_files)
          raise 'libs must be an Array when running in-process' unless Array == libs.class
          libs.reverse_each { |lib| $LOAD_PATH.unshift(lib) }
          @args = (
            cucumber_opts +
            feature_files
          ).flatten.compact
        end

        def run
          require 'cucumber/cli/main'
          failure = Cucumber::Cli::Main.execute(args)
          raise 'Cucumber failed' if failure
        end
      end

      class ForkedCucumberRunner #:nodoc:
        include ::Rake::DSL if defined?(::Rake::DSL)

        def initialize(libs, cucumber_bin, cucumber_opts, bundler, feature_files)
          @libs          = libs
          @cucumber_bin  = cucumber_bin
          @cucumber_opts = cucumber_opts
          @bundler       = bundler
          @feature_files = feature_files
        end

        def load_path
          [format('"%<path>s"', path: @libs.join(File::PATH_SEPARATOR))]
        end

        def quoted_binary(cucumber_bin)
          [format('"%<path>s"', path: cucumber_bin)]
        end

        def use_bundler
          @bundler.nil? ? File.exist?('./Gemfile') && bundler_gem_available? : @bundler
        end

        def bundler_gem_available?
          Gem::Specification.find_by_name('bundler')
        rescue Gem::LoadError
          false
        end

        def cmd
          if use_bundler
            [
              Cucumber::RUBY_BINARY, '-S', 'bundle', 'exec', 'cucumber',
              @cucumber_opts, @feature_files
            ].flatten
          else
            [
              Cucumber::RUBY_BINARY, '-I', load_path,
              quoted_binary(@cucumber_bin), @cucumber_opts, @feature_files
            ].flatten
          end
        end

        def run
          sh cmd.join(' ') do |ok, res|
            exit res.exitstatus unless ok
          end
        end
      end

      # Directories to add to the Ruby $LOAD_PATH
      attr_accessor :libs

      # Name of the cucumber binary to use for running features. Defaults to Cucumber::BINARY
      attr_accessor :binary

      # Extra options to pass to the cucumber binary. Can be overridden by the CUCUMBER_OPTS environment variable.
      # It's recommended to pass an Array, but if it's a String it will be #split by ' '.
      attr_reader :cucumber_opts
      def cucumber_opts=(opts) #:nodoc:
        @cucumber_opts = String == opts.class ? opts.split(' ') : opts
      end

      # Whether or not to fork a new ruby interpreter. Defaults to true. You may gain
      # some startup speed if you set it to false, but this may also cause issues with
      # your load path and gems.
      attr_accessor :fork

      # Define what profile to be used.  When used with cucumber_opts it is simply appended
      # to it. Will be ignored when CUCUMBER_OPTS is used.
      attr_accessor :profile

      # Whether or not to run with bundler (bundle exec). Setting this to false may speed
      # up the execution. The default value is true if Bundler is installed and you have
      # a Gemfile, false otherwise.
      #
      # Note that this attribute has no effect if you don't run in forked mode.
      attr_accessor :bundler

      # Name of the running task
      attr_reader :task_name

      # Define Cucumber Rake task
      def initialize(task_name = 'cucumber', desc = 'Run Cucumber features')
        @task_name = task_name
        @desc = desc
        @fork = true
        @libs = ['lib']
        @rcov_opts = %w[--rails --exclude osx\/objc,gems\/]
        yield self if block_given?
        @binary = binary.nil? ? Cucumber::BINARY : File.expand_path(binary)
        define_task
      end

      def define_task #:nodoc:
        desc @desc
        task @task_name do
          runner.run
        end
      end

      def runner(_task_args = nil) #:nodoc:
        cucumber_opts = [(ENV['CUCUMBER_OPTS'] ? ENV['CUCUMBER_OPTS'].split(/\s+/) : nil) || cucumber_opts_with_profile]
        return ForkedCucumberRunner.new(libs, binary, cucumber_opts, bundler, feature_files) if fork
        InProcessCucumberRunner.new(libs, cucumber_opts, feature_files)
      end

      def cucumber_opts_with_profile #:nodoc:
        Array(cucumber_opts).concat(Array(@profile).flat_map { |p| ['--profile', p] })
      end

      def feature_files #:nodoc:
        make_command_line_safe(FileList[ENV['FEATURE'] || []])
      end

      def make_command_line_safe(list)
        list.map { |string| string.gsub(' ', '\ ') }
      end
    end
  end
end
