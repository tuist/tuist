# frozen_string_literal: true

module CocoaPodsInteractor
  module Utilities
    class Output
      def self.error(message)
        $stderr.puts(message)
      end
    end
  end
end
