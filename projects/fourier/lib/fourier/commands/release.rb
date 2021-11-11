# frozen_string_literal: true

module Fourier
  module Commands
    class Release < Base
      desc "tuist VERSION", "Bundles and uploads Tuist to GCS"
      def tuist(version)
        output_directory ||= File.expand_path("build", Constants::ROOT_DIRECTORY)
        Services::Bundle::Tuist.call(output_directory: output_directory)
        Services::Bundle::Tuistenv.call(output_directory: output_directory)
        Utilities::Output.success("tuist and tuistenv were built successfully")
      end
    end
  end
end
