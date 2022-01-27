# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # This cop checks code that can be written more easily using
      # `Object#presence` defined by Active Support.
      #
      # @example
      #   # bad
      #   a.present? ? a : nil
      #
      #   # bad
      #   !a.present? ? nil : a
      #
      #   # bad
      #   a.blank? ? nil : a
      #
      #   # bad
      #   !a.blank? ? a : nil
      #
      #   # good
      #   a.presence
      #
      # @example
      #   # bad
      #   a.present? ? a : b
      #
      #   # bad
      #   !a.present? ? b : a
      #
      #   # bad
      #   a.blank? ? b : a
      #
      #   # bad
      #   !a.blank? ? a : b
      #
      #   # good
      #   a.presence || b
      class Presence < Base
        include RangeHelp
        extend AutoCorrector

        MSG = 'Use `%<prefer>s` instead of `%<current>s`.'

        def_node_matcher :redundant_receiver_and_other, <<~PATTERN
          {
            (if
              (send $_recv :present?)
              _recv
              $!begin
            )
            (if
              (send $_recv :blank?)
              $!begin
              _recv
            )
          }
        PATTERN

        def_node_matcher :redundant_negative_receiver_and_other, <<~PATTERN
          {
            (if
              (send (send $_recv :present?) :!)
              $!begin
              _recv
            )
            (if
              (send (send $_recv :blank?) :!)
              _recv
              $!begin
            )
          }
        PATTERN

        def on_if(node)
          return if ignore_if_node?(node)

          redundant_receiver_and_other(node) do |receiver, other|
            return if ignore_other_node?(other) || receiver.nil?

            register_offense(node, receiver, other)
          end

          redundant_negative_receiver_and_other(node) do |receiver, other|
            return if ignore_other_node?(other) || receiver.nil?

            register_offense(node, receiver, other)
          end
        end

        private

        def register_offense(node, receiver, other)
          add_offense(node, message: message(node, receiver, other)) do |corrector|
            corrector.replace(node.source_range, replacement(receiver, other))
          end
        end

        def ignore_if_node?(node)
          node.elsif?
        end

        def ignore_other_node?(node)
          node && (node.if_type? || node.rescue_type? || node.while_type?)
        end

        def message(node, receiver, other)
          format(MSG,
                 prefer: replacement(receiver, other),
                 current: node.source)
        end

        def replacement(receiver, other)
          or_source = if other&.send_type?
                        build_source_for_or_method(other)
                      elsif other.nil? || other.nil_type?
                        ''
                      else
                        " || #{other.source}"
                      end

          "#{receiver.source}.presence" + or_source
        end

        def build_source_for_or_method(other)
          if other.parenthesized? || other.method?('[]') || !other.arguments?
            " || #{other.source}"
          else
            method = range_between(
              other.source_range.begin_pos,
              other.first_argument.source_range.begin_pos - 1
            ).source

            arguments = other.arguments.map(&:source).join(', ')

            " || #{method}(#{arguments})"
          end
        end
      end
    end
  end
end
