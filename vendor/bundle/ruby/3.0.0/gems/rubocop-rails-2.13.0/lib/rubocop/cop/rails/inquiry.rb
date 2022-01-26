# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # This cop checks that Active Support's `inquiry` method is not used.
      #
      # @example
      #   # bad - String#inquiry
      #   ruby = 'two'.inquiry
      #   ruby.two?
      #
      #   # good
      #   ruby = 'two'
      #   ruby == 'two'
      #
      #   # bad - Array#inquiry
      #   pets = %w(cat dog).inquiry
      #   pets.gopher?
      #
      #   # good
      #   pets = %w(cat dog)
      #   pets.include? 'cat'
      #
      class Inquiry < Base
        MSG = "Prefer Ruby's comparison operators over Active Support's `inquiry`."
        RESTRICT_ON_SEND = %i[inquiry].freeze

        def on_send(node)
          return unless node.arguments.empty?
          return unless (receiver = node.receiver)
          return if !receiver.str_type? && !receiver.array_type?

          add_offense(node.loc.selector)
        end
      end
    end
  end
end
