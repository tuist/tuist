# frozen_string_literal: true

require "test_helper"
require "json"

module Fourier
  module Services
    module Lint
      class LockfilesTest < TestCase
        include TestHelpers::TemporaryDirectory
        include TestHelpers::SupressOutput

        def test_raises_when_versions_mismatch
          # Given
          tuist_lockfile = {
            "pins": [{
              "package": "Test",
              "state": { "revision": "8623e73b193386909566a9ca20203e33a09af142" },
            }] }
          spm_lockfile = {
            "pins": [{
              "package": "Test",
              "state": { "revision": "bb23e73b193386909566a9ca20203e33a09af1cc" },
            }] }
          FileUtils.mkdir_p(File.join(@tmp_dir, "Tuist/Dependencies/Lockfiles"))
          File.write(File.join(@tmp_dir, "Tuist/Dependencies/Lockfiles/Package.resolved"), tuist_lockfile.to_json)
          File.write(File.join(@tmp_dir, "Package.resolved"), spm_lockfile.to_json)

          # When/then
          assert_raises(Utilities::Errors::AbortSilentError) do
            supressing_output do
              Services::Lint::Lockfiles.call(root_directory: @tmp_dir)
            end
          end
        end

        def test_raises_when_the_number_of_packages_doesnt_match
          # Given
          tuist_lockfile = {
            "pins": [{
              "package": "Test",
              "state": { "revision": "8623e73b193386909566a9ca20203e33a09af142" },
            }] }
          spm_lockfile = {
            "pins": [
              {
                "package": "Test",
                "state": { "revision": "8623e73b193386909566a9ca20203e33a09af142" },
              },
                      {
                        "package": "Other",
                        "state": { "revision": "bb23e73b193386909566a9ca20203e33a09af1cc" },
                      },] }
          FileUtils.mkdir_p(File.join(@tmp_dir, "Tuist/Dependencies/Lockfiles"))
          File.write(File.join(@tmp_dir, "Tuist/Dependencies/Lockfiles/Package.resolved"), tuist_lockfile.to_json)
          File.write(File.join(@tmp_dir, "Package.resolved"), spm_lockfile.to_json)

          # When/then
          assert_raises(Utilities::Errors::AbortSilentError) do
            supressing_output do
              Services::Lint::Lockfiles.call(root_directory: @tmp_dir)
            end
          end
        end

        def test_doesnt_raise_when_versions_match
          # Given
          tuist_lockfile = {
            "pins": [{
              "package": "Test",
              "state": { "revision": "8623e73b193386909566a9ca20203e33a09af142" },
            }] }
          spm_lockfile = {
            "pins": [{
              "package": "Test",
              "state": { "revision": "8623e73b193386909566a9ca20203e33a09af142" },
            }] }
          FileUtils.mkdir_p(File.join(@tmp_dir, "Tuist/Dependencies/Lockfiles"))
          File.write(File.join(@tmp_dir, "Tuist/Dependencies/Lockfiles/Package.resolved"), tuist_lockfile.to_json)
          File.write(File.join(@tmp_dir, "Package.resolved"), spm_lockfile.to_json)

          # When/then
          supressing_output do
            Services::Lint::Lockfiles.call(root_directory: @tmp_dir)
          end
        end
      end
    end
  end
end
