# frozen_string_literal: true
module Fourier
  module Commands
    class Bundle < Base
      desc "tuist", "Bundle tuist"
      option(
        :output,
        desc: "The directory in which the vendored Tuist will be generated",
        type: :string,
        required: false,
        aliases: :p,
        default: "build/"
      )
      def tuist
        output_directory = options[:output]
        output_directory ||= File.expand_path("build", Constants::ROOT_DIRECTORY)
        Services::Bundle::Tuist.call(output_directory: output_directory)
      end

      desc "tuistenv", "Bundle tuistenv"
      def tuistenv
        Services::Bundle::Tuistenv.call
      end
    end
  end
end
