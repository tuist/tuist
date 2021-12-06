# frozen_string_literal: true

module CocoaPodsInteractor
  module Services
    class Install < Base
      attr_reader :path

      def initialize(path:)
        @path = path
      end

      def call
        puts "install"
      end
    end
  end
end
