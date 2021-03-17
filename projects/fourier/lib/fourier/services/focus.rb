# frozen_string_literal: true
module Fourier
  module Services
    class Focus < Base
      attr_reader :target

      def initialize(target:)
        @target = target
      end

      def call
        Dir.chdir(Constants::ROOT_DIRECTORY) do
          Utilities::System.tuist("focus", target)
        end
      end
    end
  end
end
