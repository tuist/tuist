# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # This cop checks that models subclass ApplicationRecord with Rails 5.0.
      #
      # @example
      #
      #  # good
      #  class Rails5Model < ApplicationRecord
      #    # ...
      #  end
      #
      #  # bad
      #  class Rails4Model < ActiveRecord::Base
      #    # ...
      #  end
      class ApplicationRecord < Base
        extend AutoCorrector
        extend TargetRailsVersion

        minimum_target_rails_version 5.0

        MSG = 'Models should subclass `ApplicationRecord`.'
        SUPERCLASS = 'ApplicationRecord'
        BASE_PATTERN = '(const (const nil? :ActiveRecord) :Base)'

        # rubocop:disable Layout/ClassStructure
        include RuboCop::Cop::EnforceSuperclass
        # rubocop:enable Layout/ClassStructure
      end
    end
  end
end
