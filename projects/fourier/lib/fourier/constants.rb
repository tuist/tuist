# frozen_string_literal: true

module Fourier
  module Constants
    ROOT_DIRECTORY = File.expand_path("../../../..", __dir__)
    TUIST_DIRECTORY = ROOT_DIRECTORY
    SWIFTLINT_CONFIG_PATH = File.expand_path(".swiftlint.yml", ROOT_DIRECTORY)
    FEATURES_DIRECTORY = File.expand_path("projects/tuist/features", ROOT_DIRECTORY)
    FIXTURES_DIRECTORY = File.expand_path("projects/tuist/fixtures", ROOT_DIRECTORY)
    TUIST_VENDOR_DIRECTORY = File.expand_path("projects/tuist/vendor", ROOT_DIRECTORY)
    FIXTUREGEN_DIRECTORY = File.expand_path("projects/fixturegen", ROOT_DIRECTORY)
    FOURIER_DIRECTORY = File.expand_path("projects/fourier", ROOT_DIRECTORY)
    TUISTBENCH_DIRECTORY = File.expand_path("projects/tuistbench", ROOT_DIRECTORY)
    VENDOR_DIRECTORY = File.expand_path("../../vendor", __dir__)
    REPOSITORY = "tuist/tuist"
  end
end
