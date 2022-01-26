# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # This cop enforces the consistent use of action filter methods.
      #
      # The cop is configurable and can enforce the use of the older
      # something_filter methods or the newer something_action methods.
      #
      # @example EnforcedStyle: action (default)
      #   # bad
      #   after_filter :do_stuff
      #   append_around_filter :do_stuff
      #   skip_after_filter :do_stuff
      #
      #   # good
      #   after_action :do_stuff
      #   append_around_action :do_stuff
      #   skip_after_action :do_stuff
      #
      # @example EnforcedStyle: filter
      #   # bad
      #   after_action :do_stuff
      #   append_around_action :do_stuff
      #   skip_after_action :do_stuff
      #
      #   # good
      #   after_filter :do_stuff
      #   append_around_filter :do_stuff
      #   skip_after_filter :do_stuff
      class ActionFilter < Base
        include ConfigurableEnforcedStyle
        extend AutoCorrector

        MSG = 'Prefer `%<prefer>s` over `%<current>s`.'

        FILTER_METHODS = %i[
          after_filter
          append_after_filter
          append_around_filter
          append_before_filter
          around_filter
          before_filter
          prepend_after_filter
          prepend_around_filter
          prepend_before_filter
          skip_after_filter
          skip_around_filter
          skip_before_filter
          skip_filter
        ].freeze

        ACTION_METHODS = %i[
          after_action
          append_after_action
          append_around_action
          append_before_action
          around_action
          before_action
          prepend_after_action
          prepend_around_action
          prepend_before_action
          skip_after_action
          skip_around_action
          skip_before_action
          skip_action_callback
        ].freeze

        RESTRICT_ON_SEND = FILTER_METHODS + ACTION_METHODS

        def on_block(node)
          check_method_node(node.send_node)
        end

        def on_send(node)
          check_method_node(node) unless node.receiver
        end

        private

        def check_method_node(node)
          method_name = node.method_name
          return unless bad_methods.include?(method_name)

          message = format(MSG, prefer: preferred_method(method_name), current: method_name)

          add_offense(node.loc.selector, message: message) do |corrector|
            corrector.replace(node.loc.selector, preferred_method(node.loc.selector.source))
          end
        end

        def bad_methods
          style == :action ? FILTER_METHODS : ACTION_METHODS
        end

        def good_methods
          style == :action ? ACTION_METHODS : FILTER_METHODS
        end

        def preferred_method(method)
          good_methods[bad_methods.index(method.to_sym)]
        end
      end
    end
  end
end
