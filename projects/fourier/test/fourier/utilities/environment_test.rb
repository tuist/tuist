# frozen_string_literal: true

require "test_helper"
require "semantic"

module Fourier
  module Utilities
    class EnvironmentTest < TestCase
      def test_ruby_version
        # Given
        got = Environment.ruby_version

        # Then
        assert_equal(Semantic::Version.new(RUBY_VERSION), got)
      end
    end
  end
end
