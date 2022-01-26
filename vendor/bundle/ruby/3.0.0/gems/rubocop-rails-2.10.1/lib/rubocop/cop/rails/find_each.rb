# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # This cop is used to identify usages of `all.each` and
      # change them to use `all.find_each` instead.
      #
      # @example
      #   # bad
      #   User.all.each
      #
      #   # good
      #   User.all.find_each
      #
      # @example IgnoredMethods: ['order']
      #   # good
      #   User.order(:foo).each
      class FindEach < Base
        include ActiveRecordHelper
        extend AutoCorrector

        MSG = 'Use `find_each` instead of `each`.'
        RESTRICT_ON_SEND = %i[each].freeze

        SCOPE_METHODS = %i[
          all eager_load includes joins left_joins left_outer_joins not preload
          references unscoped where
        ].freeze

        def on_send(node)
          return unless node.receiver&.send_type?
          return unless SCOPE_METHODS.include?(node.receiver.method_name)
          return if node.receiver.receiver.nil? && !inherit_active_record_base?(node)
          return if ignored?(node)

          range = node.loc.selector
          add_offense(range) do |corrector|
            corrector.replace(range, 'find_each')
          end
        end

        private

        def ignored?(node)
          method_chain = node.each_node(:send).map(&:method_name)
          (cop_config['IgnoredMethods'].map(&:to_sym) & method_chain).any?
        end
      end
    end
  end
end
