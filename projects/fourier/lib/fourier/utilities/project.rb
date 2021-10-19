# frozen_string_literal: true

require "semantic"

module Fourier
  module Utilities
    module Project
      def self.ruby_version
        path = File.join(Constants::ROOT_DIRECTORY, ".ruby-version")
        Semantic::Version.new(File.read(path))
      end
    end
  end
end
