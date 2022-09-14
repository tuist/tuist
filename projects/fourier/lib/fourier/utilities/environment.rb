# frozen_string_literal: true

require "semantic"

module Fourier
  module Utilities
    module Environment
      class << self
        def ruby_version
          Semantic::Version.new(RUBY_VERSION)
        end
      end
    end
  end
end
