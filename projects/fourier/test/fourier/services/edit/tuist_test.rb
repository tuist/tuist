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
            .with("edit", "--only-current-directory", source: false)

          # Then
          Services::Edit::Tuist.call(source: false)
        end
      end
    end
  end
end
