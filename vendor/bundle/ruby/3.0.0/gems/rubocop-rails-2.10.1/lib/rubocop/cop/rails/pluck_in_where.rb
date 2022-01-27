# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # This cop identifies places where `pluck` is used in `where` query methods
      # and can be replaced with `select`.
      #
      # Since `pluck` is an eager method and hits the database immediately,
      # using `select` helps to avoid additional database queries.
      #
      # This cop has two different enforcement modes. When the EnforcedStyle
      # is conservative (the default) then only calls to `pluck` on a constant
      # (i.e. a model class) in the `where` is used as offenses.
      #
      # When the EnforcedStyle is aggressive then all calls to `pluck` in the
      # `where` is used as offenses. This may lead to false positives
      # as the cop cannot replace to `select` between calls to `pluck` on an
      # `ActiveRecord::Relation` instance vs a call to `pluck` on an `Array` instance.
      #
      # @example
      #   # bad
      #   Post.where(user_id: User.active.pluck(:id))
      #
      #   # good
      #   Post.where(user_id: User.active.select(:id))
      #   Post.where(user_id: active_users.select(:id))
      #
      # @example EnforcedStyle: conservative (default)
      #   # good
      #   Post.where(user_id: active_users.pluck(:id))
      #
      # @example EnforcedStyle: aggressive
      #   # bad
      #   Post.where(user_id: active_users.pluck(:id))
      #
      class PluckInWhere < Base
        include ActiveRecordHelper
        include ConfigurableEnforcedStyle
        extend AutoCorrector

        MSG = 'Use `select` instead of `pluck` within `where` query method.'
        RESTRICT_ON_SEND = %i[pluck].freeze

        def on_send(node)
          return unless in_where?(node)
          return if style == :conservative && !root_receiver(node)&.const_type?

          range = node.loc.selector

          add_offense(range) do |corrector|
            corrector.replace(range, 'select')
          end
        end

        private

        def root_receiver(node)
          receiver = node.receiver

          if receiver&.send_type?
            root_receiver(receiver)
          else
            receiver
          end
        end
      end
    end
  end
end
