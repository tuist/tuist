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
        :use_default_xcode,
        default: false,
        desc: "Whether or not to use the default Xcode version on the build device",
        type: :boolean,
        required: false,
        aliases: :d,
      )
      def tuist
        output_directory = options[:output]
        output_directory ||= File.expand_path("build", Constants::ROOT_DIRECTORY)
        use_default_xcode = options[:use_default_xcode] || false
        Services::Bundle::Tuist.call(
          output_directory: output_directory,
          use_default_xcode: use_default_xcode
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
      def tuistenv
        output_directory = options[:output]
        output_directory ||= File.expand_path("build", Constants::ROOT_DIRECTORY)
        Services::Bundle::Tuistenv.call(output_directory: output_directory)
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
        :use_default_xcode,
        desc: "Whether or not to use the default Xcode version on the build device (For building the `tuist` binary only. Building `tuistenv` always uses the default Xcode version.",
        type: :boolean,
        required: false,
        aliases: :d,
      )
      def all
        output_directory = options[:output]
        output_directory ||= File.expand_path("build", Constants::ROOT_DIRECTORY)
        use_default_xcode = options[:use_default_xcode] || false

        bundle_all(output_directory: output_directory, use_default_xcode: use_default_xcode)
      end
      no_commands {
        def bundle_all(output_directory:, use_default_xcode:)
          Services::Bundle::Tuist.call(
            output_directory: output_directory,
            use_default_xcode: use_default_xcode
          )
          Services::Bundle::Tuistenv.call(
            output_directory: output_directory
          )
        end
      }
    end
  end
end
