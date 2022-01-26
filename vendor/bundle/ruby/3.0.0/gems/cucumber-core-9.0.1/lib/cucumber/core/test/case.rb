# frozen_string_literal: true

require 'cucumber/core/test/result'
require 'cucumber/tag_expressions'

module Cucumber
  module Core
    module Test
      class Case
        attr_reader :id, :name, :test_steps, :location, :tags, :language, :around_hooks

        def initialize(id, name, test_steps, location, tags, language, around_hooks = [])
          raise ArgumentError.new("test_steps should be an Array but is a #{test_steps.class}") unless test_steps.is_a?(Array)
          @id = id
          @name = name
          @test_steps = test_steps
          @location = location
          @tags = tags
          @language = language
          @around_hooks = around_hooks
        end

        def step_count
          test_steps.count
        end

        def describe_to(visitor, *args)
          visitor.test_case(self, *args) do |child_visitor|
            compose_around_hooks(child_visitor, *args) do
              test_steps.each do |test_step|
                test_step.describe_to(child_visitor, *args)
              end
            end
          end
          self
        end

        def with_steps(test_steps)
          self.class.new(id, name, test_steps, location, tags, language, around_hooks)
        end

        def with_around_hooks(around_hooks)
          self.class.new(id, name, test_steps, location, tags, language, around_hooks)
        end

        def match_tags?(*expressions)
          expressions.flatten.all? { |expression| match_single_tag_expression?(expression) }
        end

        def match_name?(name_regexp)
          name =~ name_regexp
        end

        def match_locations?(queried_locations)
          queried_locations.any? do |queried_location|
            queried_location.match? location
          end
        end

        def inspect
          "#<#{self.class}: #{location}>"
        end

        def hash
          location.hash
        end

        def eql?(other)
          other.hash == hash
        end

        def ==(other)
          eql?(other)
        end

        private

        def compose_around_hooks(visitor, *args, &block)
          around_hooks.reverse.reduce(block) do |continue, hook|
            -> { hook.describe_to(visitor, *args, &continue) }
          end.call
        end

        def match_single_tag_expression?(expression)
          Cucumber::TagExpressions::Parser.new.parse(expression).evaluate(tags.map(&:name))
        end
      end
    end
  end
end
