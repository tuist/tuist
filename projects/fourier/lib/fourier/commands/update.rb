# frozen_string_literal: true

module Fourier
  module Commands
    class Update < Base
      desc "swiftlint", "Update the vendored swiftlint binary"
      def swiftlint
        puts(::CLI::UI.fmt("Updating {{info:swiftlint}}"))
        Services::Update::Swiftlint.call
      end

      desc "xcbeautify", "Update the vendored xcbeautify binary"
      def xcbeautify
        puts(::CLI::UI.fmt("Updating {{info:xcbeautify}}"))
        Services::Update::Xcbeautify.call
      end

      desc "all", "Update all the vendored tools"
      def all
        swiftlint
        xcbeautify
      end
    end
  end
end
