# frozen_string_literal: true

module Cucumber
  module StepMatchSearch
    def self.new(search, configuration)
      CachesStepMatch.new(
        AssertUnambiguousMatch.new(
          configuration.guess? ? AttemptToGuessAmbiguousMatch.new(search) : search,
          configuration
        )
      )
    end

    class AssertUnambiguousMatch
      def initialize(search, configuration)
        @search = search
        @configuration = configuration
      end

      def call(step_name)
        result = @search.call(step_name)
        raise Cucumber::Ambiguous.new(step_name, result, @configuration.guess?) if result.length > 1
        result
      end
    end

    class AttemptToGuessAmbiguousMatch
      def initialize(search)
        @search = search
      end

      def call(step_name)
        best_matches(step_name, @search.call(step_name))
      end

      private

      def best_matches(_step_name, step_matches) #:nodoc:
        no_groups      = step_matches.select { |step_match| step_match.args.empty? }
        max_arg_length = step_matches.map { |step_match| step_match.args.length }.max
        top_groups     = step_matches.select { |step_match| step_match.args.length == max_arg_length }

        if no_groups.any?
          longest_regexp_length = no_groups.map(&:text_length).max
          no_groups.select { |step_match| step_match.text_length == longest_regexp_length }
        elsif top_groups.any?
          shortest_capture_length = top_groups.map { |step_match| step_match.args.inject(0) { |sum, c| sum + c.to_s.length } }.min
          top_groups.select { |step_match| step_match.args.inject(0) { |sum, c| sum + c.to_s.length } == shortest_capture_length }
        else
          top_groups
        end
      end
    end

    require 'delegate'
    class CachesStepMatch < SimpleDelegator
      def call(step_name) #:nodoc:
        @match_cache ||= {}

        matches = @match_cache[step_name]
        return matches if matches

        @match_cache[step_name] = super(step_name)
      end
    end
  end
end
