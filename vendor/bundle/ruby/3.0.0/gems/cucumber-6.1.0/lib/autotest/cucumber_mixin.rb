# frozen_string_literal: true

require 'autotest'
require 'tempfile'
require 'cucumber'
require 'cucumber/cli/profile_loader'

module Autotest::CucumberMixin
  def self.included(receiver)
    receiver::ALL_HOOKS << %i[run_features ran_features]
  end

  attr_accessor :features_to_run

  def initialize
    super
    reset_features
  end

  def run
    hook :initialize
    reset
    reset_features
    add_sigint_handler

    loop do # ^c handler
      get_to_green
      if tainted
        rerun_all_tests
        rerun_all_features if all_good
      else
        hook :all_good
      end
      wait_for_changes
      # Once tests and features are green, reset features every
      # time a file is changed to see if anything breaks.
      reset_features
    rescue Interrupt
      break if wants_to_quit
      reset
      reset_features
    end
    hook :quit
  end

  def all_features_good
    features_to_run == ''
  end

  def get_to_green # rubocop:disable Naming/AccessorMethodName
    loop do
      super
      run_features
      wait_for_changes unless all_features_good
      break if all_features_good
    end
  end

  def rerun_all_features
    reset_features
    run_features
  end

  def reset_features
    self.features_to_run = :all
  end

  def run_features
    hook :run_features
    Tempfile.open('autotest-cucumber') do |dirty_features_file|
      cmd = make_cucumber_cmd(features_to_run, dirty_features_file.path)
      break if cmd.empty?
      old_sync = $stdout.sync
      $stdout.sync = true
      self.results = []
      line = []
      begin
        open("| #{cmd}", 'r') do |f| # rubocop:disable Security/Open
          until f.eof?
            c = f.getc || break
            print(c)
            line << c
            next unless c == "\n"
            results << line.join
            line.clear
          end
        end
      ensure
        $stdout.sync = old_sync
      end
      self.features_to_run = dirty_features_file.read.strip
      self.tainted = true unless features_to_run == ''
    end
    hook :ran_features
  end

  def make_cucumber_cmd(features_to_run, _dirty_features_filename)
    return '' if features_to_run.empty?

    profile_loader = Cucumber::Cli::ProfileLoader.new

    profile = profile(profile_loader)

    args = created_args(features_to_run, profile)

    "#{Cucumber::RUBY_BINARY} #{Cucumber::BINARY} #{args}"
  end

  def profile(profile_loader)
    profile ||= 'autotest-all' if profile_loader.profile?('autotest-all') && features_to_run == :all
    profile ||= 'autotest'     if profile_loader.profile?('autotest')
    profile || nil
  end

  def created_args(features_to_run, profile)
    args = if profile
             ['--profile', profile]
           else
             %w[--format] << (features_to_run == :all ? 'progress' : 'pretty')
           end
    # No --color option as some IDEs (Netbeans) don't output them very well ([31m1 failed step[0m)
    args += %w[--format rerun --out] << dirty_features_filename
    args << (features_to_run == :all ? '' : features_to_run)

    # All steps becom undefined during rerun unless the following is run.
    args << 'features/step_definitions' << 'features/support' unless features_to_run == :all

    args.join(' ')
  end
end
