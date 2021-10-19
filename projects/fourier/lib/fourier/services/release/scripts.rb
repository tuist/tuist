# frozen_string_literal: true

module Fourier
  module Services
    module Release
      class Scripts < Base
        attr_reader :storage

        def initialize(
          storage: Fourier::Utilities::GoogleCloudStorage.new
        )
          @storage = storage
        end


        def call
          bucket = storage.bucket(Constants::GoogleCloud::RELEASES_BUCKET)
          install_path = File.expand_path("script/install", Constants::ROOT_DIRECTORY)
          uninstall_path = File.expand_path("script/uninstall", Constants::ROOT_DIRECTORY)

          bucket.create_file(install_path, "scripts/install").acl.public!
          bucket.create_file(uninstall_path, "scripts/uninstall").acl.public!
        end
      end
    end
  end
end
