# frozen_string_literal: true
require "cucumber/cli/main"

module Fourier
  module Services
    module Test
      module Tuist
        class Acceptance < Base
          Error = Class.new(StandardError)

          attr_reader :feature

          def initialize(feature:)
            @feature = feature
          end

          def call
            args = ["--format", "pretty"]

            args << if feature.nil?
              File.join(Constants::TUIST_DIRECTORY, "features/")
            else
              feature
            end

            failure = Cucumber::Cli::Main.execute(args)
            raise Error, "Cucumber failed" if failure
          end
        end
      end
    end
  end
end
