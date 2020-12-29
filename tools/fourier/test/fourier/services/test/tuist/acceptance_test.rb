# frozen_string_literal: true
require "test_helper"
require 'cucumber/cli/main'

module Fourier
  module Services
    module Test
      module Tuist
        class AcceptanceTest < TestCase
          def test_call_when_feature_is_provided
            # Given
            path = "/path/to/feature.feature"
            ::Cucumber::Cli::Main
              .expects(:execute)
              .with(["--format", "pretty", path])

            # Then
            Acceptance.call(feature: path)
          end

          def test_call_when_no_feature_is_provided
            # Given
            ::Cucumber::Cli::Main
              .expects(:execute)
              .with(["--format", "pretty", File.join(Constants::ROOT_DIRECTORY, "features/")])

            # Then
            Acceptance.call(feature: nil)
          end

          def test_raises_when_cucumber_returns_unsuncessfully
            # Given
            cucumber_error = StandardError.new("cucumber error")
            ::Cucumber::Cli::Main
              .expects(:execute)
              .with(["--format", "pretty", File.join(Constants::ROOT_DIRECTORY, "features/")])
              .returns(cucumber_error)

            # When
            error = assert_raises(Acceptance::Error) do
              Acceptance.call(feature: nil)
            end

            # Then
            assert_equal('Cucumber failed', error.message)
          end
        end
      end
    end
  end
end
