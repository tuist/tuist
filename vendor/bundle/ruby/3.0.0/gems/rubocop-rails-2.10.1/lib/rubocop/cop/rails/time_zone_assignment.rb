# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # This cop checks for the use of `Time.zone=` method.
      #
      # The `zone` attribute persists for the rest of the Ruby runtime, potentially causing
      # unexpected behaviour at a later time.
      # Using `Time.use_zone` ensures the code passed in block is the only place Time.zone is affected.
      # It eliminates the possibility of a `zone` sticking around longer than intended.
      #
      # @example
      #   # bad
      #   Time.zone = 'EST'
      #
      #   # good
      #   Time.use_zone('EST') do
      #   end
      #
      class TimeZoneAssignment < Base
        MSG = 'Use `Time.use_zone` with blocks instead of `Time.zone=`.'
        RESTRICT_ON_SEND = %i[zone=].freeze

        def_node_matcher :time_zone_assignement?, <<~PATTERN
          (send (const nil? :Time) :zone= ...)
        PATTERN

        def on_send(node)
          return unless time_zone_assignement?(node)

          add_offense(node)
        end
      end
    end
  end
end
