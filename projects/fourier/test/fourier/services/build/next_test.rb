# frozen_string_literal: true
require "test_helper"

module Fourier
  module Services
    module Build
      class NextTest < TestCase
        def test_runs_the_website
          # Given
          Utilities::System.expects(:system).with("yarn", "build")

          # Then
          Services::Build::Web.call
        end
      end
    end
  end
end
