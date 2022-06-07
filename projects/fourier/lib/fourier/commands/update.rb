# frozen_string_literal: true

module Fourier
  module Commands
    class Update < Base
      desc "swiftformat", "Update the vendored swiftformat binary"
      option(
        :xcode_version,
        desc: %(
          The version of Xcode to use to build tuist.
          Can be either a version number (e.g. `--xcode_version="13.2.1"`)
          or a file path pointing to the Xcode app bundle to use. (e.g. `--xcode_version="/path/to/Xcode.app"`)
          Defaults to the currently selected Xcode on the system.
        ),
        type: :string,
        required: false
      )
      option(
        :xcode_version_libraries,
        desc: %(
          The version of Xcode to use to build tuist's library dependencies.
          Can be either a version number (e.g. `--xcode_version="13.2.1"`)
          or a file path pointing to the Xcode app bundle to use. (e.g. `--xcode_version="/path/to/Xcode.app"`)
          Defaults to the currently selected Xcode on the system.
        ),
        type: :string,
        required: false
      )

      def swiftformat
        xcode_paths = Utilities::Xcode::Paths.new(
          default: options[:xcode_version],
          libraries: options[:xcode_version_libraries]
        )

        Dir.mktmpdir do |swift_build_directory|
          puts(::CLI::UI.fmt("Updating {{info:swiftformat}}"))
          Services::Update::Swiftformat.call(
            swift_build_directory: swift_build_directory,
            xcode_paths: xcode_paths
          )
        end
      end

      desc "swiftlint", "Update the vendored swiftlint binary"
      def swiftlint
        puts(::CLI::UI.fmt("Updating {{info:swiftlint}}"))
        Services::Update::Swiftlint.call
      end

      desc "xcbeautify", "Update the vendored xcbeautify binary"
      option(
        :xcode_version,
        desc: %(
          The version of Xcode to use to build tuist.
          Can be either a version number (e.g. `--xcode_version="13.2.1"`)
          or a file path pointing to the Xcode app bundle to use. (e.g. `--xcode_version="/path/to/Xcode.app"`)
          Defaults to the currently selected Xcode on the system.
        ),
        type: :string,
        required: false
      )
      option(
        :xcode_version_libraries,
        desc: %(
          The version of Xcode to use to build tuist's library dependencies.
          Can be either a version number (e.g. `--xcode_version="13.2.1"`)
          or a file path pointing to the Xcode app bundle to use. (e.g. `--xcode_version="/path/to/Xcode.app"`)
          Defaults to the currently selected Xcode on the system.
        ),
        type: :string,
        required: false
      )
      def xcbeautify
        xcode_paths = Utilities::Xcode::Paths.new(
          default: options[:xcode_version],
          libraries: options[:xcode_version_libraries]
        )

        Dir.mktmpdir do |swift_build_directory|
          puts(::CLI::UI.fmt("Updating {{info:xcbeautify}}"))
          Services::Update::Xcbeautify.call(
            swift_build_directory: swift_build_directory,
            xcode_paths: xcode_paths
          )
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
