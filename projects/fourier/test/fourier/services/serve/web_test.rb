# frozen_string_literal: true

require "test_helper"

module Fourier
  module Services
    module Serve
      class WebTest < TestCase
        def test_runs_the_website
          # Given
          Utilities::System.expects(:system).with("yarn", "develop")

          # Then
          Services::Serve::Web.call
        end
      end
    end
  end
end
