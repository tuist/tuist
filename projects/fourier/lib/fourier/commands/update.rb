# frozen_string_literal: true

module Fourier
  module Commands
    class Update < Base
      desc "swiftformat", "Update the vendored swiftformat binary"
      def swiftformat
        Dir.mktmpdir do |swift_build_directory|
          puts(::CLI::UI.fmt("Updating {{info:swiftformat}}"))
          Services::Update::Swiftformat.call(swift_build_directory: swift_build_directory)
        end
      end

      desc "swiftlint", "Update the vendored swiftlint binary"
      def swiftlint
        puts(::CLI::UI.fmt("Updating {{info:swiftlint}}"))
        Services::Update::Swiftlint.call
      end

      desc "xcbeautify", "Update the vendored xcbeautify binary"
      def xcbeautify
        Dir.mktmpdir do |swift_build_directory|
          puts(::CLI::UI.fmt("Updating {{info:xcbeautify}}"))
          Services::Update::Xcbeautify.call(swift_build_directory: swift_build_directory)
        end
      end

      desc "all", "Update all the vendored tools"
      def all
        swiftlint
        xcbeautify
      end
    end
  end
end
