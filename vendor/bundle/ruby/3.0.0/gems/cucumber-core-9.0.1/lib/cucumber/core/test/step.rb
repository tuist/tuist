# frozen_string_literal: true

require 'cucumber/core/test/result'
require 'cucumber/core/test/action'
require 'cucumber/core/test/empty_multiline_argument'

module Cucumber
  module Core
    module Test
      class Step
        attr_reader :id, :text, :location, :multiline_arg

        def initialize(id, text, location, multiline_arg = Test::EmptyMultilineArgument.new, action = Test::UndefinedAction.new(location))
          raise ArgumentError if text.nil? || text.empty?
          @id = id
          @text = text
          @location = location
          @multiline_arg = multiline_arg
          @action = action
        end

        def describe_to(visitor, *args)
          visitor.test_step(self, *args)
        end

        def hook?
          false
        end

        def skip(*args)
          @action.skip(*args)
        end

        def execute(*args)
          @action.execute(*args)
        end

        def with_action(action_location = nil, &block)
          self.class.new(id, text, location, multiline_arg, Test::Action.new(action_location, &block))
        end

        def backtrace_line
          "#{location}:in `#{text}'"
        end

        def to_s
          text
        end

        def action_location
          @action.location
        end

        def inspect
          "#<#{self.class}: #{location}>"
        end
      end

      class HookStep < Step
        def initialize(id, text, location, action)
          super(id, text, location, Test::EmptyMultilineArgument.new, action)
        end

        def hook?
          true
        end
      end
    end
  end
end
