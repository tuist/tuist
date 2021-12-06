# frozen_string_literal: true

module CocoaPodsInteractor
  module Utilities
    class Output
      def self.error(message)
        STDERR.puts(message)
      end
    end
  end
end
