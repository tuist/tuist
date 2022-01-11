# frozen_string_literal: true

require "tmpdir"

module Fourier
  module Commands
    class Bundle < Base
      desc "tuist", "Bundle tuist"
      option(
        :output,
        desc: "The directory in which the vendored tuist will be generated",
        type: :string,
        required: false,
        aliases: :p,
      )
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
      def tuist
        output_directory = options[:output]
        output_directory ||= File.expand_path("build", Constants::ROOT_DIRECTORY)

        xcode_paths = Utilities::Xcode::Paths.new(
          default: options[:xcode_version],
          libraries: options[:xcode_version_libraries]
        )

        Services::Bundle::Tuist.call(
          output_directory: output_directory,
          xcode_paths: xcode_paths
        )
      end

      desc "tuistenv", "Bundle tuistenv"
      option(
        :output,
        desc: "The directory in which the vendored tuistenv will be generated",
        type: :string,
        required: false,
        aliases: :p,
      )
      option(
        :xcode_version,
        desc: %(
          The version of Xcode to use to build tuistenv.
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
          The version of Xcode to use to build tuistenv's library dependencies.
          Can be either a version number (e.g. `--xcode_version="13.2.1"`)
          or a file path pointing to the Xcode app bundle to use. (e.g. `--xcode_version="/path/to/Xcode.app"`)
          Defaults to the currently selected Xcode on the system.
        ),
        type: :string,
        required: false
      )
      def tuistenv
        output_directory = options[:output]
        output_directory ||= File.expand_path("build", Constants::ROOT_DIRECTORY)

        xcode_paths = Utilities::Xcode::Paths.new(
          default: options[:xcode_version],
          libraries: options[:xcode_version_libraries]
        )

        Services::Bundle::Tuistenv.call(
          output_directory: output_directory,
          xcode_paths: xcode_paths
        )
      end

      desc "all", "Bundle tuistenv and tuist"
      option(
        :output,
        desc: "The directory in which the vendored tuist and tuistenv will be generated",
        type: :string,
        required: false,
        aliases: :p,
      )
      option(
        :build,
        desc: "The directory to be used for building",
        type: :string,
        required: false,
        aliases: :b,
      )
      option(
        :xcode_version,
        desc: %(
          The version of Xcode to use to build tuist and tuistenv.
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
          The version of Xcode to use to build tuist and tuistenv's library dependencies.
          Can be either a version number (e.g. `--xcode_version="13.2.1"`)
          or a file path pointing to the Xcode app bundle to use. (e.g. `--xcode_version="/path/to/Xcode.app"`)
          Defaults to the currently selected Xcode on the system.
        ),
        type: :string,
        required: false
      )
      def all
        output_directory = options[:output]
        output_directory ||= File.expand_path("build", Constants::ROOT_DIRECTORY)

        xcode_paths = Utilities::Xcode::Paths.new(
          default: options[:xcode_version],
          libraries: options[:xcode_version_libraries]
        )

        bundle_all(
          output_directory: output_directory,
          xcode_paths: xcode_paths
        )
      end

      no_commands {
        def bundle_all(
          output_directory:,
          xcode_paths:
        )
          Services::Bundle::Tuist.call(
            output_directory: output_directory,
            xcode_paths: xcode_paths
          )
          Services::Bundle::Tuistenv.call(
            output_directory: output_directory,
            xcode_paths: xcode_paths
          )
        end
      }
    end
  end
end
