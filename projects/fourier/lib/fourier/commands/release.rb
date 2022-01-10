# frozen_string_literal: true

module Fourier
  module Commands
    class Release < Base
      desc "tuist VERSION", "Bundles and uploads Tuist to GCS"
      def tuist(
        version,
        xcode_version = nil,
        xcode_version_libraries = nil
      )
        output_directory ||= File.expand_path("build", Constants::ROOT_DIRECTORY)

        xcode_paths = Utilities::Xcode::Paths.new(
          default: xcode_version,
          libraries: xcode_version_libraries
        )

        Services::Bundle::Tuist.call(
          output_directory: output_directory,
          xcode_paths: xcode_paths
        )

        Services::Bundle::Tuistenv.call(
          output_directory: output_directory,
          xcode_paths: xcode_paths
        )

        Utilities::Output.success("tuist and tuistenv were built successfully")
      end
    end
  end
end
