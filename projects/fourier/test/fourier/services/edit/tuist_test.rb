# frozen_string_literal: true

require "test_helper"

module Fourier
  module Services
    module Edit
      class TuistTest < TestCase
        def test_call
          # Given
          Utilities::System
            .expects(:tuist)
            .with("edit", "--only-current-directory")

          # Then
          Services::Edit::Tuist.call
        end
      end
    end
  end
end
