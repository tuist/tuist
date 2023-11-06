# frozen_string_literal: true

module Fourier
  module Constants
    ROOT_DIRECTORY = File.expand_path("../../../..", __dir__)
    TUIST_DIRECTORY = ROOT_DIRECTORY
    SWIFTLINT_CONFIG_PATH = File.expand_path(".swiftlint.yml", ROOT_DIRECTORY)
    FIXTURES_DIRECTORY = File.expand_path("projects/tuist/fixtures", ROOT_DIRECTORY)
    FOURIER_DIRECTORY = File.expand_path("projects/fourier", ROOT_DIRECTORY)
    REPOSITORY = "tuist/tuist"
  end
end
