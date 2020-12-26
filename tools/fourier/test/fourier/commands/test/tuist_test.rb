# frozen_string_literal: true
require "test_helper"

module Fourier
  module Commands
    class Test < Base
      class TuistTest < TestCase
        def test_unit
          # Given
          Utilities::System
            .expects(:system)
            .with("swift", "test", "--package-path", root_directory)
          subject = Tuist.new

          # When/Then
          subject.unit
        end
      end
    end
  end
end
