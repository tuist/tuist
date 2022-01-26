# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # This cop checks that controllers subclass ApplicationController.
      #
      # @example
      #
      #  # good
      #  class MyController < ApplicationController
      #    # ...
      #  end
      #
      #  # bad
      #  class MyController < ActionController::Base
      #    # ...
      #  end
      class ApplicationController < Base
        extend AutoCorrector

        MSG = 'Controllers should subclass `ApplicationController`.'
        SUPERCLASS = 'ApplicationController'
        BASE_PATTERN = '(const (const nil? :ActionController) :Base)'

        # rubocop:disable Layout/ClassStructure
        include RuboCop::Cop::EnforceSuperclass
        # rubocop:enable Layout/ClassStructure
      end
    end
  end
end
