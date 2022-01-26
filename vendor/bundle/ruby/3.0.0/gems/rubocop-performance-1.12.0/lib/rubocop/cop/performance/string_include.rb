# frozen_string_literal: true

module RuboCop
  module Cop
    module Performance
      # This cop identifies unnecessary use of a regex where
      # `String#include?` would suffice.
      #
      # @safety
      #   This cop's offenses are not safe to auto-correct if a receiver is nil.
      #
      # @example
      #   # bad
      #   'abc'.match?(/ab/)
      #   /ab/.match?('abc')
      #   'abc' =~ /ab/
      #   /ab/ =~ 'abc'
      #   'abc'.match(/ab/)
      #   /ab/.match('abc')
      #
      #   # good
      #   'abc'.include?('ab')
      class StringInclude < Base
        extend AutoCorrector

        MSG = 'Use `String#include?` instead of a regex match with literal-only pattern.'
        RESTRICT_ON_SEND = %i[match =~ match?].freeze

        def_node_matcher :redundant_regex?, <<~PATTERN
          {(send $!nil? {:match :=~ :match?} (regexp (str $#literal?) (regopt)))
           (send (regexp (str $#literal?) (regopt)) {:match :match?} $str)
           (match-with-lvasgn (regexp (str $#literal?) (regopt)) $_)}
        PATTERN

        def on_send(node)
          return unless (receiver, regex_str = redundant_regex?(node))

          add_offense(node) do |corrector|
            receiver, regex_str = regex_str, receiver if receiver.is_a?(String)
            regex_str = interpret_string_escapes(regex_str)

            new_source = "#{receiver.source}.include?(#{to_string_literal(regex_str)})"

            corrector.replace(node.source_range, new_source)
          end
        end
        alias on_match_with_lvasgn on_send

        private

        def literal?(regex_str)
          regex_str.match?(/\A#{Util::LITERAL_REGEX}+\z/o)
        end
      end
    end
  end
end
