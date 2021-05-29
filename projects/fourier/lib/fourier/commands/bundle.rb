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
      def tuist
        output_directory = options[:output]
        output_directory ||= File.expand_path("build", Constants::ROOT_DIRECTORY)
        Services::Bundle::Tuist.call(output_directory: output_directory)
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
      def all
        output_directory = options[:output]
        output_directory ||= File.expand_path("build", Constants::ROOT_DIRECTORY)

        Dir.mktmpdir do |tmp_dir|
          Services::Bundle::Tuist.call(
            output_directory: output_directory,
            build_directory: tmp_dir
          )
          Services::Bundle::Tuistenv.call(
            output_directory: output_directory,
            build_directory: tmp_dir
          )
        end
      end
    end
  end
end
