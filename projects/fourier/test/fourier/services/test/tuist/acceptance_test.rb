# frozen_string_literal: true

require "test_helper"
require "cucumber/cli/main"

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
              .with(["--format", "pretty", "--strict-undefined", "--require", Constants::FEATURES_DIRECTORY, path])

            # Then
            Acceptance.call(feature: path)
          end

          def test_call_when_no_feature_is_provided
            # Given
            @subject = Acceptance.new(feature: nil)
            ::Cucumber::Cli::Main
              .expects(:execute)
              .with([
                "--format",
"pretty",
"--strict-undefined",
"--require",
Constants::FEATURES_DIRECTORY,
Constants::FEATURES_DIRECTORY,])

            # Then
            @subject.call
          end

          def test_raises_when_cucumber_returns_unsuncessfully
            # Given
            cucumber_error = StandardError.new("cucumber error")
            @subject = Acceptance.new(feature: nil)
            ::Cucumber::Cli::Main
              .expects(:execute)
              .with([
                "--format",
"pretty",
"--strict-undefined",
"--require",
Constants::FEATURES_DIRECTORY,
Constants::FEATURES_DIRECTORY,])
              .returns(cucumber_error)

            # When
            error = assert_raises(Acceptance::Error) do
              @subject.call
            end

            # Then
            assert_equal("Cucumber failed", error.message)
          end
        end
      end
    end
  end
end
