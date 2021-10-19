# frozen_string_literal: true

require "semantic"

module Fourier
  module Utilities
    module Environment
      def self.ruby_version
        Semantic::Version.new(RUBY_VERSION)
      end
    end
  end
end
