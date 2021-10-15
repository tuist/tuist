# frozen_string_literal: true

require "test_helper"
require "semantic"

module Fourier
  module Utilities
    class ProjectTest < TestCase
      def test_ruby_version
        # Given
        got = Project.ruby_version

        # Then
        path = File.join(Constants::ROOT_DIRECTORY, ".ruby-version")
        assert_equal(Semantic::Version.new(File.read(path)), got)
      end
    end
  end
end
