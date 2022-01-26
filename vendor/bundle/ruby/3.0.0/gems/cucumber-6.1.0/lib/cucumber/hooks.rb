# frozen_string_literal: true

require 'pathname'
require 'cucumber/core/test/location'
require 'cucumber/core/test/around_hook'

module Cucumber
  # Hooks quack enough like `Cucumber::Core::Ast` source nodes that we can use them as
  # source for test steps
  module Hooks
    class << self
      def before_hook(id, location, &block)
        build_hook_step(id, location, block, BeforeHook, Core::Test::UnskippableAction)
      end

      def after_hook(id, location, &block)
        build_hook_step(id, location, block, AfterHook, Core::Test::UnskippableAction)
      end

      def after_step_hook(id, test_step, location, &block)
        raise ArgumentError if test_step.hook?
        build_hook_step(id, location, block, AfterStepHook, Core::Test::Action)
      end

      def around_hook(&block)
        Core::Test::AroundHook.new(&block)
      end

      private

      def build_hook_step(id, location, block, hook_type, action_type)
        action = action_type.new(location, &block)
        hook = hook_type.new(action.location)
        Core::Test::HookStep.new(id, hook.text, location, action)
      end
    end

    class AfterHook
      attr_reader :location

      def initialize(location)
        @location = location
      end

      def text
        'After hook'
      end

      def to_s
        "#{text} at #{location}"
      end

      def match_locations?(queried_locations)
        queried_locations.any? { |other_location| other_location.match?(location) }
      end

      def describe_to(visitor, *args)
        visitor.after_hook(self, *args)
      end
    end

    class BeforeHook
      attr_reader :location

      def initialize(location)
        @location = location
      end

      def text
        'Before hook'
      end

      def to_s
        "#{text} at #{location}"
      end

      def match_locations?(queried_locations)
        queried_locations.any? { |other_location| other_location.match?(location) }
      end

      def describe_to(visitor, *args)
        visitor.before_hook(self, *args)
      end
    end

    class AfterStepHook
      attr_reader :location

      def initialize(location)
        @location = location
      end

      def text
        'AfterStep hook'
      end

      def to_s
        "#{text} at #{location}"
      end

      def match_locations?(queried_locations)
        queried_locations.any? { |other_location| other_location.match?(location) }
      end

      def describe_to(visitor, *args)
        visitor.after_step_hook(self, *args)
      end
    end
  end
end
