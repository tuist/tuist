# frozen_string_literal: true

require "json"

module Fourier
  module Services
    module Lint
      class Lockfiles < Base
        attr_reader :root_directory

        def initialize(root_directory: Constants::ROOT_DIRECTORY)
          @root_directory = root_directory
        end

        def call
          spm_lockfile = self.spm_lockfile
          tuist_lockfile = self.tuist_lockfile
          same_versions = assert_same_versions(spm_lockfile: spm_lockfile, tuist_lockfile: tuist_lockfile)
          same_count = assert_same_packages_count(spm_lockfile: spm_lockfile, tuist_lockfile: tuist_lockfile)
          valid = same_versions && same_count
          raise Utilities::Errors::AbortSilentError unless valid
        end

        private
          def assert_same_packages_count(spm_lockfile:, tuist_lockfile:)
            return true if spm_lockfile.count == tuist_lockfile.count

            message = "The number of packages in the Package.resolved files don't match."
            Utilities::Output.error(message)
            false
          end

          def assert_same_versions(spm_lockfile:, tuist_lockfile:)
            mismatched_packages = []
            common_packages = spm_lockfile.keys & tuist_lockfile.keys

            common_packages.each do |package_name|
              tuist_revision = tuist_lockfile[package_name]["state"]["revision"]
              spm_revision = spm_lockfile[package_name]["state"]["revision"]
              mismatched_packages << package_name if tuist_revision != spm_revision
            end

            if mismatched_packages.count != 0
              message = "There's a mismatch between the revision of the following pakages in"\
                " in the Package.resolved files:"\
                " #{mismatched_packages.join(", ")}"
              Utilities::Output.error(message)
              return false
            end
            true
          end

          def spm_lockfile
            path = File.expand_path("Package.resolved", root_directory)
            load_lockfile(path)
          end

          def tuist_lockfile
            path = File.expand_path("Tuist/Dependencies/Lockfiles/Package.resolved", root_directory)
            load_lockfile(path)
          end

          def load_lockfile(path)
            content = JSON.parse(File.read(path))["object"]["pins"]
            content.inject({}) do |acc, package|
              acc[package["package"]] = package
              acc
            end
          end
      end
    end
  end
end
