# frozen_string_literal: true

module RuboCop
  module Cop
    # This module encapsulates the ability to allow certain methods when
    # parsing.
    module AllowedMethods
      private

      # @api public
      def allowed_method?(name)
        allowed_methods.include?(name.to_s)
      end

      # @api public
      def allowed_methods
        cop_config.fetch('AllowedMethods', [])
      end
    end
  end
end
