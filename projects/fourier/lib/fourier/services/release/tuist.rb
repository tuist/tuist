# frozen_string_literal: true
module Fourier
  module Services
    module Release
      class Tuist < Base
        attr_reader :tuistenv_zip_path, :tuist_zip_path, :storage, :version

        def initialize(
          version:,
          tuistenv_zip_path:,
          tuist_zip_path:,
          storage: Utilities::GoogleCloudStorage.new()
        )
          @version = version
          @tuistenv_zip_path = tuistenv_zip_path
          @tuist_zip_path = tuist_zip_path
          @storage = storage
        end

        def call
          bucket = storage.bucket(Constants::GoogleCloud::RELEASES_BUCKET)

          bucket.create_file(tuist_zip_path, "#{version}/tuist.zip").acl.public!
          bucket.create_file(tuistenv_zip_path, "#{version}/tuistenv.zip").acl.public!

          bucket.create_file(tuist_zip_path, "latest/tuist.zip").acl.public!
          bucket.create_file(tuistenv_zip_path, "latest/tuistenv.zip").acl.public!

          Dir.mktmpdir do |tmp_dir|
            version_path = File.join(tmp_dir, "version")
            File.write(version_path, version)
            bucket.create_file(version_path, "latest/version").acl.public!
          end
        end
      end
    end
  end
end
