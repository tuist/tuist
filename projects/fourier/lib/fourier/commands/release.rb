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
        Utilities::Output.section("Uploading tuist and tuistenv scripts to GCS...")
        Services::Release::Tuist.call(
          version: version,
          tuistenv_zip_path: File.join(output_directory, "tuist.zip"),
          tuist_zip_path: File.join(output_directory, "tuistenv.zip"),
        )
        Utilities::Output.success("tuist and tuistenv uploaded to GCS")
      end

      desc "scripts", "Bundles and uploads the installation scripts to GCS"
      def scripts
        Utilities::Secrets.decrypt
        Utilities::Output.section("Uploading installation scripts to GCS...")
        Services::Release::Scripts.call
        Utilities::Output.success("Scripts successfully uploaded")
      end
    end
  end
end
