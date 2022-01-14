# frozen_string_literal: true

module Fourier
  module Services
    class Focus < Base
      attr_reader :targets, :source

      def initialize(targets: [], source: false)
        @targets = targets
        @source = source
      end

      def call
        targets = @targets.uniq

        if targets.empty?
          Utilities::Output.section("Focusing on all targets.")
          Utilities::Output.subsection("Use --targets to specify targets")
        else
          Utilities::Output.section("Focusing on targets: #{targets.join(", ")}")
        end

        dependencies = ["dependencies", "fetch"]
        Utilities::System.tuist(*dependencies, source: @source)

        cache_warm = ["cache", "warm", "--dependencies-only"]
        Utilities::System.tuist(*cache_warm, source: @source)

        focus = ["focus"] + targets
        Utilities::System.tuist(*focus, source: @source)
      end
    end
  end
end
