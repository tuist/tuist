# frozen_string_literal: true

require 'cucumber/platform'
module Cucumber
  module Glue
    # Utility methods for executing step definitions with nice backtraces etc.
    # TODO: add unit tests
    # TODO: refactor for readability
    class InvokeInWorld
      def self.replace_instance_exec_invocation_line!(backtrace, instance_exec_invocation_line, pseudo_method)
        return if Cucumber.use_full_backtrace

        instance_exec_pos = backtrace.index(instance_exec_invocation_line)
        return unless instance_exec_pos
        replacement_line = instance_exec_pos + INSTANCE_EXEC_OFFSET
        backtrace[replacement_line].gsub!(/`.*'/, "`#{pseudo_method}'") if pseudo_method

        depth = backtrace.count { |line| line == instance_exec_invocation_line }
        end_pos = depth > 1 ? instance_exec_pos : -1

        backtrace[replacement_line + 1..end_pos] = nil
        backtrace.compact!
      end

      def self.cucumber_instance_exec_in(world, check_arity, pseudo_method, *args, &block)
        cucumber_run_with_backtrace_filtering(pseudo_method) do
          if check_arity && !cucumber_compatible_arity?(args, block)
            world.instance_exec do
              ari = block.arity
              ari = ari < 0 ? (ari.abs - 1).to_s + '+' : ari
              s1 = ari == 1 ? '' : 's'
              s2 = args.length == 1 ? '' : 's'
              raise ArityMismatchError, "Your block takes #{ari} argument#{s1}, but the Regexp matched #{args.length} argument#{s2}."
            end
          else
            world.instance_exec(*args, &block)
          end
        end
      end

      def self.cucumber_compatible_arity?(args, block)
        return true if block.arity == args.length
        if block.arity < 0
          return true if args.length >= (block.arity.abs - 1)
        end
        false
      end

      def self.cucumber_run_with_backtrace_filtering(pseudo_method)
        yield
      rescue Exception => e # rubocop:disable Lint/RescueException
        instance_exec_invocation_line = "#{__FILE__}:#{__LINE__ - 2}:in `cucumber_run_with_backtrace_filtering'"
        replace_instance_exec_invocation_line!((e.backtrace || []), instance_exec_invocation_line, pseudo_method)
        raise e
      end

      INSTANCE_EXEC_OFFSET = -3
    end

    # Raised if the number of a StepDefinition's Regexp match groups
    # is different from the number of Proc arguments.
    class ArityMismatchError < StandardError
    end
  end
end
