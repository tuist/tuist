# frozen_string_literal: true

module RuboCop
  module Cop
    module Performance
      # This cop identifies places where `gsub(/a+/, 'a')` and `gsub!(/a+/, 'a')`
      # can be replaced by `squeeze('a')` and `squeeze!('a')`.
      #
      # The `squeeze('a')` method is faster than `gsub(/a+/, 'a')`.
      #
      # @example
      #
      #   # bad
      #   str.gsub(/a+/, 'a')
      #   str.gsub!(/a+/, 'a')
      #
      #   # good
      #   str.squeeze('a')
      #   str.squeeze!('a')
      #
      class Squeeze < Base
        extend AutoCorrector

        MSG = 'Use `%<prefer>s` instead of `%<current>s`.'
        RESTRICT_ON_SEND = %i[gsub gsub!].freeze

        PREFERRED_METHODS = {
          gsub: :squeeze,
          gsub!: :squeeze!
        }.freeze

        def_node_matcher :squeeze_candidate?, <<~PATTERN
          (send
            $!nil? ${:gsub :gsub!}
            (regexp
              (str $#repeating_literal?)
              (regopt))
            (str $_))
        PATTERN

        def on_send(node)
          squeeze_candidate?(node) do |receiver, bad_method, regexp_str, replace_str|
            regexp_str = regexp_str[0..-2] # delete '+' from the end
            regexp_str = interpret_string_escapes(regexp_str)
            return unless replace_str == regexp_str

            good_method = PREFERRED_METHODS[bad_method]
            message = format(MSG, current: bad_method, prefer: good_method)

            add_offense(node.loc.selector, message: message) do |corrector|
              string_literal = to_string_literal(replace_str)
              new_code = "#{receiver.source}.#{good_method}(#{string_literal})"

              corrector.replace(node.source_range, new_code)
            end
          end
        end

        private

        def repeating_literal?(regex_str)
          regex_str.match?(/\A(?:#{Util::LITERAL_REGEX})\+\z/o)
        end
      end
    end
  end
end
