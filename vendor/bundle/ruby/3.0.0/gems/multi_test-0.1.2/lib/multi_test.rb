require 'multi_test/assertion_library'
module MultiTest
  def self.disable_autorun
    if defined?(Test::Unit::Runner)
      Test::Unit::Runner.module_eval("@@stop_auto_run = true")
    end

    if defined?(Minitest)
      Minitest.instance_eval do
        def run(*)
          # propagate the exit code from cucumber or another runner
          case $!
          when SystemExit
            $!.status
          else
            true
          end
        end
      end

      if defined?(Minitest::Unit)
        Minitest::Unit.class_eval do
          def run(*)
          end
        end
      end
    end
  end

  def self.extend_with_best_assertion_library(object)
    AssertionLibrary.detect_best.extend_world(object)
  end
end
