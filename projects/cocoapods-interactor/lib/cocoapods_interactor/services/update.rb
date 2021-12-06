# frozen_string_literal: true

module CocoaPodsInteractor
  module Services
    class Update < Base
      attr_reader :path

      def initialize(path:)
        @path = path
      end

      def call
        puts "update"
      end
    end
  end
end
