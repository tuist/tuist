require_relative "../../test_helper"
require "minitest/mock"

module MinitestReportersTest
  class ReportersTest < Minitest::Test
    def test_chooses_the_rubymine_reporter_when_necessary
      # Rubymine reporter complains when RubyMine libs are not available, so
      # stub its #puts method out.
      $stdout.stub :puts, nil do
        reporters = Minitest::Reporters.choose_reporters [], { "RM_INFO" => "x" }
        assert_instance_of Minitest::Reporters::RubyMineReporter, reporters[0]

        reporters = Minitest::Reporters.choose_reporters [], { "TEAMCITY_VERSION" => "x" }
        assert_instance_of Minitest::Reporters::RubyMineReporter, reporters[0]
      end
    end

    def test_chooses_the_textmate_reporter_when_necessary
      reporters = Minitest::Reporters.choose_reporters [], {"TM_PID" => "x"}
      assert_instance_of Minitest::Reporters::RubyMateReporter, reporters[0]
    end

    def test_chooses_the_console_reporters_when_necessary
      reporters = Minitest::Reporters.choose_reporters [Minitest::Reporters::SpecReporter.new], {}
      assert_instance_of Minitest::Reporters::SpecReporter, reporters[0]
    end

    def test_chooses_no_reporters_when_running_under_vim
      reporters = Minitest::Reporters.choose_reporters(
        [Minitest::Reporters::DefaultReporter.new], { "VIM" => "/usr/share/vim" })
      assert_nil reporters
    end

    def test_chooses_given_reporter_when_MINITEST_REPORTERS_env_set
      env = {
        "MINITEST_REPORTER" => "JUnitReporter", 
        "RM_INFO" => "x", 
        "TEAMCITY_VERSION" => "x", 
        "TM_PID" => "x" }
      # JUnit reporter init has stdout messages... capture them to keep test output clean
      $stdout.stub :puts, nil do
        reporters = Minitest::Reporters.choose_reporters [], env
        assert_instance_of Minitest::Reporters::JUnitReporter, reporters[0]
      end
    end

    def test_uses_minitest_clock_time_when_minitest_version_greater_than_561
      Minitest::Reporters.stub :minitest_version, 583 do
        Minitest.stub :clock_time, 6765.378751009 do
          clock_time = Minitest::Reporters.clock_time
          assert_equal 6765.378751009, clock_time
        end
      end
    end

    def test_uses_minitest_clock_time_when_minitest_version_less_than_561
      Minitest::Reporters.stub :minitest_version, 431 do
        Time.stub :now, Time.new(2015, 11, 20, 17, 35) do
          clock_time = Minitest::Reporters.clock_time
          assert_equal Time.new(2015, 11, 20, 17, 35), clock_time
        end
      end
    end
  end
end
