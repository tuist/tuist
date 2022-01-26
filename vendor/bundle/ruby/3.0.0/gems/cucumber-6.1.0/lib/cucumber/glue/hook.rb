# frozen_string_literal: true

require 'cucumber/glue/invoke_in_world'

module Cucumber
  module Glue
    # TODO: Kill pointless wrapper for Before, After and AfterStep hooks with fire
    class Hook
      attr_reader :id, :tag_expressions, :location

      def initialize(id, registry, tag_expressions, proc)
        @id = id
        @registry = registry
        @tag_expressions = sanitize_tag_expressions(tag_expressions)
        @proc = proc
        @location = Cucumber::Core::Test::Location.from_source_location(*@proc.source_location)
        fail_for_old_style_tag_expressions(@tag_expressions)
      end

      def invoke(pseudo_method, arguments, &block)
        check_arity = false
        InvokeInWorld.cucumber_instance_exec_in(
          @registry.current_world,
          check_arity,
          pseudo_method,
          *[arguments, block].flatten.compact,
          &@proc
        )
      end

      def to_envelope
        Cucumber::Messages::Envelope.new(
          hook: Cucumber::Messages::Hook.new(
            id: id,
            tag_expression: tag_expressions.join(' '),
            source_reference: Cucumber::Messages::SourceReference.new(
              uri: location.file,
              location: Cucumber::Messages::Location.new(
                line: location.lines.first
              )
            )
          )
        )
      end

      private

      def sanitize_tag_expressions(tag_expressions)
        # TODO: remove when '~@no-clobber' has been changed to 'not @no-clobber' in aruba
        tag_expressions.map { |tag_expression| tag_expression == '~@no-clobber' ? 'not @no-clobber' : tag_expression }
      end

      def fail_for_old_style_tag_expressions(tag_expressions)
        tag_expressions.each do |tag_expression|
          if tag_expression.include?('~')
            raise("Found tagged hook with '#{tag_expression}'." \
            "'~@tag' is no longer supported, use 'not @tag' instead.")
          end

          next unless tag_expression.include?(',')
          warn("Found tagged hook with '#{tag_expression}'." \
            "'@tag1,@tag2' is no longer supported, use '@tag or @tag2' instead.")
        end
      end
    end
  end
end
