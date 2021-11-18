# frozen_string_literal: true

module Fourier
  module Services
    class Focus < Base
      attr_reader :target

      def initialize(target:)
        @target = target
      end

      def call
        dependencies = ["dependencies", "fetch"]
        Utilities::System.tuist(*dependencies)

        cache_warm = ["cache", "warm", "--dependencies-only"]
        Utilities::System.tuist(*cache_warm)

        focus = ["focus"]
        focus << "#{target}" if target != nil
        Utilities::System.tuist(*focus)
      end
    end
  end
end
