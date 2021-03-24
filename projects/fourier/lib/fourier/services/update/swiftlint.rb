# frozen_string_literal: true

module Fourier
  module Services
    module Update
      class Swiftlint < Base
        def call
          # SWIFTLINT_VERSION = "0.43.1"

          # root_dir = File.expand_path(__dir__)
          # Dir.mktmpdir do |temporary_dir|
          #   Dir.chdir(temporary_dir) do
          #     system("curl", "-LO",
          #       "https://github.com/realm/SwiftLint/releases/download/#{SWIFTLINT_VERSION}/portable_swiftlint.zip")
          #     extract_zip("portable_swiftlint.zip", "portable_swiftlint")
          #     system("cp", "portable_swiftlint/swiftlint", "#{root_dir}/vendor/swiftlint")
          #   end
          # end
          # File.write(File.join(root_dir, "vendor/.swiftlint.version"), SWIFTLINT_VERSION)
        end
      end
    end
  end
end
