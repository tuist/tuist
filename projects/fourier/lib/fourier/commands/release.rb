# frozen_string_literal: true
module Fourier
  module Commands
    class Release < Base
      desc "tuist VERSION", "Bundles and uploads Tuist to GCS"
      def tuist(version)
        Utilities::Secrets.decrypt

        output_directory ||= File.expand_path("build", Constants::ROOT_DIRECTORY)
        Services::Bundle::Tuist.call(output_directory: output_directory)
        Services::Bundle::Tuistenv.call(output_directory: output_directory)
      end

      desc "scripts", "Bundles and uploads the installation scripts to GCS"
      def scripts
        Utilities::Secrets.decrypt
      end
    end
  end
end
