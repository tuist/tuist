module CLI
  module Kit
    module Support
      module TestHelper
        def setup
          super
          CLI::Kit::System.reset!
        end

        def assert_all_commands_run(should_raise: true)
          errors = CLI::Kit::System.error_message
          CLI::Kit::System.reset!
          assert false, errors if should_raise && !errors.nil?
          errors
        end

        def teardown
          super
          assert_all_commands_run
        end

        module FakeConfig
          require 'tmpdir'
          require 'fileutils'

          def setup
            super
            @tmpdir = Dir.mktmpdir
            @prev_xdg = ENV['XDG_CONFIG_HOME']
            ENV['XDG_CONFIG_HOME'] = @tmpdir
          end

          def teardown
            FileUtils.rm_rf(@tmpdir)
            ENV['XDG_CONFIG_HOME'] = @prev_xdg
            super
          end
        end

        class FakeSuccess
          def initialize(success)
            @success = success
          end

          def success?
            @success
          end
        end

        module ::CLI
          module Kit
            module System
              class << self
                alias_method :original_system, :system
                def system(*a, sudo: false, env: {}, **kwargs)
                  expected_command = expected_command(*a, sudo: sudo, env: env)

                  # In the case of an unexpected command, expected_command will be nil
                  return FakeSuccess.new(false) if expected_command.nil?

                  # Otherwise handle the command
                  if expected_command[:allow]
                    original_system(*a, sudo: sudo, env: env, **kwargs)
                  else
                    FakeSuccess.new(expected_command[:success])
                  end
                end

                alias_method :original_capture2, :capture2
                def capture2(*a, sudo: false, env: {}, **kwargs)
                  expected_command = expected_command(*a, sudo: sudo, env: env)

                  # In the case of an unexpected command, expected_command will be nil
                  return [nil, FakeSuccess.new(false)] if expected_command.nil?

                  # Otherwise handle the command
                  if expected_command[:allow]
                    original_capture2(*a, sudo: sudo, env: env, **kwargs)
                  else
                    [
                      expected_command[:stdout],
                      FakeSuccess.new(expected_command[:success]),
                    ]
                  end
                end

                alias_method :original_capture2e, :capture2e
                def capture2e(*a, sudo: false, env: {}, **kwargs)
                  expected_command = expected_command(*a, sudo: sudo, env: env)

                  # In the case of an unexpected command, expected_command will be nil
                  return [nil, FakeSuccess.new(false)] if expected_command.nil?

                  # Otherwise handle the command
                  if expected_command[:allow]
                    original_capture2ecapture2e(*a, sudo: sudo, env: env, **kwargs)
                  else
                    [
                      expected_command[:stdout],
                      FakeSuccess.new(expected_command[:success]),
                    ]
                  end
                end

                alias_method :original_capture3, :capture3
                def capture3(*a, sudo: false, env: {}, **kwargs)
                  expected_command = expected_command(*a, sudo: sudo, env: env)

                  # In the case of an unexpected command, expected_command will be nil
                  return [nil, nil, FakeSuccess.new(false)] if expected_command.nil?

                  # Otherwise handle the command
                  if expected_command[:allow]
                    original_capture3(*a, sudo: sudo, env: env, **kwargs)
                  else
                    [
                      expected_command[:stdout],
                      expected_command[:stderr],
                      FakeSuccess.new(expected_command[:success]),
                    ]
                  end
                end

                # Sets up an expectation for a command and stubs out the call (unless allow is true)
                #
                # #### Parameters
                # `*a` : the command, represented as a splat
                # `stdout` : stdout to stub the command with (defaults to empty string)
                # `stderr` : stderr to stub the command with (defaults to empty string)
                # `allow` : allow determines if the command will be actually run, or stubbed. Defaults to nil (stub)
                # `success` : success status to stub the command with (Defaults to nil)
                # `sudo` : expectation of sudo being set or not (defaults to false)
                # `env` : expectation of env being set or not (defaults to {})
                #
                # Note: Must set allow or success
                #
                def fake(*a, stdout: "", stderr: "", allow: nil, success: nil, sudo: false, env: {})
                  raise ArgumentError, "success or allow must be set" if success.nil? && allow.nil?

                  @delegate_open3 ||= {}
                  @delegate_open3[a.join(' ')] = {
                    expected: {
                      sudo: sudo,
                      env: env,
                    },
                    actual: {
                      sudo: nil,
                      env: nil,
                    },
                    stdout: stdout,
                    stderr: stderr,
                    allow: allow,
                    success: success,
                    run: false,
                  }
                end

                # Resets the faked commands
                #
                def reset!
                  @delegate_open3 = {}
                end

                # Returns the errors associated to a test run
                #
                # #### Returns
                # `errors` (String) a string representing errors found on this run, nil if none
                def error_message
                  errors = {
                    unexpected: [],
                    not_run: [],
                    other: {},
                  }

                  @delegate_open3.each do |cmd, opts|
                    if opts[:unexpected]
                      errors[:unexpected] << cmd
                    elsif opts[:run]
                      error = []

                      if opts[:expected][:sudo] != opts[:actual][:sudo]
                        error << "- sudo was supposed to be #{opts[:expected][:sudo]} but was #{opts[:actual][:sudo]}"
                      end

                      if opts[:expected][:env] != opts[:actual][:env]
                        error << "- env was supposed to be #{opts[:expected][:env]} but was #{opts[:actual][:env]}"
                      end

                      errors[:other][cmd] = error.join("\n") unless error.empty?
                    else
                      errors[:not_run] << cmd
                    end
                  end

                  final_error = []

                  unless errors[:unexpected].empty?
                    final_error << CLI::UI.fmt(<<~EOF)
                    {{bold:Unexpected command invocations:}}
                    {{command:#{errors[:unexpected].join("\n")}}}
                    EOF
                  end

                  unless errors[:not_run].empty?
                    final_error << CLI::UI.fmt(<<~EOF)
                    {{bold:Expected commands were not run:}}
                    {{command:#{errors[:not_run].join("\n")}}}
                    EOF
                  end

                  unless errors[:other].empty?
                    final_error << CLI::UI.fmt(<<~EOF)
                    {{bold:Commands were not run as expected:}}
                    #{errors[:other].map { |cmd, msg| "{{command:#{cmd}}}\n#{msg}" }.join("\n\n")}
                    EOF
                  end

                  return nil if final_error.empty?
                  "\n" + final_error.join("\n") # Initial new line for formatting reasons
                end

                private

                def expected_command(*a, sudo: raise, env: raise)
                  expected_cmd = @delegate_open3[a.join(' ')]

                  if expected_cmd.nil?
                    @delegate_open3[a.join(' ')] = { unexpected: true }
                    return nil
                  end

                  expected_cmd[:run] = true
                  expected_cmd[:actual][:sudo] = sudo
                  expected_cmd[:actual][:env] = env
                  expected_cmd
                end
              end
            end
          end
        end
      end
    end
  end
end
