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
        Services::Bundle::Tuist.call(output_directory: options[:output])
      end

      desc "tuistenv", "Bundle tuistenv"
      def tuistenv
        Services::Bundle::Tuistenv.call
      end
    end
  end
end
