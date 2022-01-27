# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # This cop checks for expanded date range. It only compatible `..` range is targeted.
      # Incompatible `...` range is ignored.
      #
      # @example
      #   # bad
      #   date.beginning_of_day..date.end_of_day
      #   date.beginning_of_week..date.end_of_week
      #   date.beginning_of_month..date.end_of_month
      #   date.beginning_of_quarter..date.end_of_quarter
      #   date.beginning_of_year..date.end_of_year
      #
      #   # good
      #   date.all_day
      #   date.all_week
      #   date.all_month
      #   date.all_quarter
      #   date.all_year
      #
      class ExpandedDateRange < Base
        extend AutoCorrector
        extend TargetRailsVersion

        MSG = 'Use `%<preferred_method>s` instead.'

        minimum_target_rails_version 5.1

        def_node_matcher :expanded_date_range, <<~PATTERN
          (irange
            (send
              $_ {:beginning_of_day :beginning_of_week :beginning_of_month :beginning_of_quarter :beginning_of_year})
            (send
              $_ {:end_of_day :end_of_week :end_of_month :end_of_quarter :end_of_year}))
        PATTERN

        PREFERRED_METHODS = {
          beginning_of_day: 'all_day',
          beginning_of_week: 'all_week',
          beginning_of_month: 'all_month',
          beginning_of_quarter: 'all_quarter',
          beginning_of_year: 'all_year'
        }.freeze

        MAPPED_DATE_RANGE_METHODS = {
          beginning_of_day: :end_of_day,
          beginning_of_week: :end_of_week,
          beginning_of_month: :end_of_month,
          beginning_of_quarter: :end_of_quarter,
          beginning_of_year: :end_of_year
        }.freeze

        def on_irange(node)
          return unless expanded_date_range(node)

          begin_node = node.begin
          end_node = node.end
          return unless same_receiver?(begin_node, end_node)

          beginning_method = begin_node.method_name
          end_method = end_node.method_name
          return unless use_mapped_methods?(beginning_method, end_method)

          preferred_method = "#{begin_node.receiver.source}.#{PREFERRED_METHODS[beginning_method]}"

          add_offense(node, message: format(MSG, preferred_method: preferred_method)) do |corrector|
            corrector.replace(node, preferred_method)
          end
        end

        private

        def same_receiver?(begin_node, end_node)
          begin_node.receiver.source == end_node.receiver.source
        end

        def use_mapped_methods?(beginning_method, end_method)
          MAPPED_DATE_RANGE_METHODS[beginning_method] == end_method
        end
      end
    end
  end
end
