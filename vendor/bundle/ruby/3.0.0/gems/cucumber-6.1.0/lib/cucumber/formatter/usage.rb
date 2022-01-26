# frozen_string_literal: true

require 'cucumber/formatter/progress'
require 'cucumber/step_definition_light'

module Cucumber
  module Formatter
    class Usage < Progress
      class StepDefKey < StepDefinitionLight
        attr_accessor :mean_duration, :status
      end

      def initialize(config)
        super
        @stepdef_to_match = Hash.new { |h, stepdef_key| h[stepdef_key] = [] }
        @total_duration = 0
        @matches = {}
        config.on_event :step_activated do |event|
          test_step, step_match = *event.attributes
          @matches[test_step.to_s] = step_match
        end
        config.on_event :step_definition_registered, &method(:on_step_definition_registered)
      end

      def on_step_definition_registered(event)
        stepdef_key = StepDefKey.new(event.step_definition.expression.to_s, event.step_definition.location)
        @stepdef_to_match[stepdef_key] = []
      end

      def on_step_match(event)
        @matches[event.test_step.to_s] = event.step_match
        super
      end

      def on_test_step_finished(event)
        return if event.test_step.hook?

        test_step = event.test_step
        result = event.result.with_filtered_backtrace(Cucumber::Formatter::BacktraceFilter)
        step_match = @matches[test_step.to_s]

        unless step_match.nil?
          step_definition = step_match.step_definition
          stepdef_key = StepDefKey.new(step_definition.expression.to_s, step_definition.location)
          unless @stepdef_to_match[stepdef_key].map { |key| key[:location] }.include? test_step.location
            duration = DurationExtractor.new(result).result_duration
            keyword = @ast_lookup.step_source(test_step).step.keyword

            @stepdef_to_match[stepdef_key] << {
              keyword: keyword,
              step_match: step_match,
              status: result.to_sym,
              location: test_step.location,
              duration: duration
            }
          end
        end

        super
      end

      private

      def print_summary
        aggregate_info

        keys = if config.dry_run?
                 @stepdef_to_match.keys.sort_by(&:regexp_source)
               else
                 @stepdef_to_match.keys.sort_by(&:mean_duration).reverse
               end

        keys.each do |stepdef_key|
          print_step_definition(stepdef_key)

          if @stepdef_to_match[stepdef_key].any?
            print_steps(stepdef_key)
          else
            @io.puts('  ' + format_string('NOT MATCHED BY ANY STEPS', :failed))
          end
        end
        @io.puts
        super
      end

      def print_step_definition(stepdef_key)
        @io.print format_string(format('%<duration>.7f', duration: stepdef_key.mean_duration), :skipped) + ' ' unless config.dry_run?
        @io.print format_string(stepdef_key.regexp_source, stepdef_key.status)
        if config.source?
          indent = max_length - stepdef_key.regexp_source.unpack('U*').length
          line_comment = "   # #{stepdef_key.location}".indent(indent)
          @io.print(format_string(line_comment, :comment))
        end
        @io.puts
      end

      def print_steps(stepdef_key)
        @stepdef_to_match[stepdef_key].each do |step|
          @io.print '  '
          @io.print format_string(format('%<duration>.7f', duration: step[:duration]), :skipped) + ' ' unless config.dry_run?
          @io.print format_step(step[:keyword], step[:step_match], step[:status], nil)
          if config.source?
            indent = max_length - (step[:keyword].unpack('U*').length + step[:step_match].format_args.unpack('U*').length)
            line_comment = " # #{step[:location]}".indent(indent)
            @io.print(format_string(line_comment, :comment))
          end
          @io.puts
        end
      end

      def max_length
        [max_stepdef_length, max_step_length].compact.max
      end

      def max_stepdef_length
        @stepdef_to_match.keys.flatten.map { |key| key.regexp_source.unpack('U*').length }.max
      end

      def max_step_length
        @stepdef_to_match.values.to_a.flatten.map do |step|
          step[:keyword].unpack('U*').length + step[:step_match].format_args.unpack('U*').length
        end.max
      end

      def aggregate_info
        @stepdef_to_match.each do |key, steps|
          if steps.empty?
            key.status = :skipped
            key.mean_duration = 0
          else
            key.status = worst_status(steps.map { |step| step[:status] })
            total_duration = steps.inject(0) { |sum, step| step[:duration] + sum }
            key.mean_duration = total_duration / steps.length
          end
        end
      end

      def worst_status(statuses)
        %i[passed undefined pending skipped failed].find do |status|
          statuses.include?(status)
        end
      end
    end
  end
end
