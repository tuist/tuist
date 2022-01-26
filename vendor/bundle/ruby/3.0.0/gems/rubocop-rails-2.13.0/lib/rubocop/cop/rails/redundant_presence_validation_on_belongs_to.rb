# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # Since Rails 5.0 the default for `belongs_to` is `optional: false`
      # unless `config.active_record.belongs_to_required_by_default` is
      # explicitly set to `false`. The presence validator is added
      # automatically, and explicit presence validation is redundant.
      #
      # @example
      #   # bad
      #   belongs_to :user
      #   validates :user, presence: true
      #
      #   # bad
      #   belongs_to :user
      #   validates :user_id, presence: true
      #
      #   # bad
      #   belongs_to :author, foreign_key: :user_id
      #   validates :user_id, presence: true
      #
      #   # good
      #   belongs_to :user
      #
      #   # good
      #   belongs_to :author, foreign_key: :user_id
      #
      class RedundantPresenceValidationOnBelongsTo < Base
        include RangeHelp
        extend AutoCorrector
        extend TargetRailsVersion

        MSG = 'Remove explicit presence validation for `%<association>s`.'
        RESTRICT_ON_SEND = %i[validates].freeze

        minimum_target_rails_version 5.0

        # @!method presence_validation?(node)
        #   Match a `validates` statement with a presence check
        #
        #   @example source that matches - by association
        #     validates :user, presence: true
        #
        #   @example source that matches - with presence options
        #     validates :user, presence: { message: 'duplicate' }
        #
        #   @example source that matches - by a foreign key
        #     validates :user_id, presence: true
        def_node_matcher :presence_validation?, <<~PATTERN
          $(
            send nil? :validates
            (sym $_)
            ...
            $(hash <$(pair (sym :presence) {true hash}) ...>)
          )
        PATTERN

        # @!method optional_option?(node)
        #  Match a `belongs_to` association with an optional option in a hash
        def_node_matcher :optional?, <<~PATTERN
          (send nil? :belongs_to _ ... #optional_option?)
        PATTERN

        # @!method optional_option?(node)
        #  Match an optional option in a hash
        def_node_matcher :optional_option?, <<~PATTERN
          {
            (hash <(pair (sym :optional) true) ...>)   # optional: true
            (hash <(pair (sym :required) false) ...>)  # required: false
          }
        PATTERN

        # @!method any_belongs_to?(node, association:)
        #   Match a class with `belongs_to` with no regard to `foreign_key` option
        #
        #   @example source that matches
        #     belongs_to :user
        #
        #   @example source that matches - regardless of `foreign_key`
        #     belongs_to :author, foreign_key: :user_id
        #
        #   @param node [RuboCop::AST::Node]
        #   @param association [Symbol]
        #   @return [Array<RuboCop::AST::Node>, nil] matching node
        def_node_matcher :any_belongs_to?, <<~PATTERN
          (begin
            <
              $(send nil? :belongs_to (sym %association) ...)
              ...
            >
          )
        PATTERN

        # @!method belongs_to?(node, key:, fk:)
        #   Match a class with a matching association, either by name or an explicit
        #   `foreign_key` option
        #
        #   @example source that matches - fk matches `foreign_key` option
        #     belongs_to :author, foreign_key: :user_id
        #
        #   @example source that matches - key matches association name
        #     belongs_to :user
        #
        #   @example source that does not match - explicit `foreign_key` does not match
        #     belongs_to :user, foreign_key: :account_id
        #
        #   @param node [RuboCop::AST::Node]
        #   @param key [Symbol] e.g. `:user`
        #   @param fk [Symbol] e.g. `:user_id`
        #   @return [Array<RuboCop::AST::Node>] matching nodes
        def_node_matcher :belongs_to?, <<~PATTERN
          (begin
            <
              ${
                #belongs_to_without_fk?(%key)         # belongs_to :user
                #belongs_to_with_a_matching_fk?(%fk)  # belongs_to :author, foreign_key: :user_id
              }
              ...
            >
          )
        PATTERN

        # @!method belongs_to_without_fk?(node, fk)
        #   Match a matching `belongs_to` association, without an explicit `foreign_key` option
        #
        #   @param node [RuboCop::AST::Node]
        #   @param key [Symbol] e.g. `:user`
        #   @return [Array<RuboCop::AST::Node>] matching nodes
        def_node_matcher :belongs_to_without_fk?, <<~PATTERN
          {
            (send nil? :belongs_to (sym %1))        # belongs_to :user
            (send nil? :belongs_to (sym %1) !hash)  # belongs_to :user, -> { not_deleted }
            (send nil? :belongs_to (sym %1) !(hash <(pair (sym :foreign_key) _) ...>))
          }
        PATTERN

        # @!method belongs_to_with_a_matching_fk?(node, fk)
        #   Match a matching `belongs_to` association with a matching explicit `foreign_key` option
        #
        #   @example source that matches
        #     belongs_to :author, foreign_key: :user_id
        #
        #   @param node [RuboCop::AST::Node]
        #   @param fk [Symbol] e.g. `:user_id`
        #   @return [Array<RuboCop::AST::Node>] matching nodes
        def_node_matcher :belongs_to_with_a_matching_fk?, <<~PATTERN
          (send nil? :belongs_to ... (hash <(pair (sym :foreign_key) (sym %1)) ...>))
        PATTERN

        def on_send(node)
          validation, key, options, presence = presence_validation?(node)
          return unless validation

          belongs_to = belongs_to_for(node.parent, key)
          return unless belongs_to
          return if optional?(belongs_to)

          message = format(MSG, association: key.to_s)

          add_offense(presence, message: message) do |corrector|
            remove_presence_validation(corrector, node, options, presence)
          end
        end

        private

        def belongs_to_for(model_class_node, key)
          if key.to_s.end_with?('_id')
            normalized_key = key.to_s.delete_suffix('_id').to_sym
            belongs_to?(model_class_node, key: normalized_key, fk: key)
          else
            any_belongs_to?(model_class_node, association: key)
          end
        end

        def remove_presence_validation(corrector, node, options, presence)
          if options.children.one?
            corrector.remove(range_by_whole_lines(node.source_range, include_final_newline: true))
          else
            range = range_with_surrounding_comma(
              range_with_surrounding_space(range: presence.source_range, side: :left),
              :left
            )
            corrector.remove(range)
          end
        end
      end
    end
  end
end
