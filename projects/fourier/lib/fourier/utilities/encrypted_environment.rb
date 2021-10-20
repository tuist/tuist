# frozen_string_literal: true

require "json"
require "tmpdir"
require "fileutils"

module Fourier
  module Utilities
    module EncryptedEnvironment
      EnvironmentError = Class.new(StandardError)
      MissingEjson = Class.new(EnvironmentError)

      def self.load_from_ejson(ejson_path, private_key: nil)
        decrypt_environment(
          ejson_path: ejson_path,
          private_key: private_key
        ).each do |key, value|
          ENV[key] = value if key != "_public_key"
        end
      end

      def self.encrypt_ejson(ejson_path, private_key: nil)
        with_secrets(ejson_path: ejson_path, private_key: private_key) do |path|
          %x(EJSON_KEYDIR=#{path} #{binary_path} encrypt #{ejson_path})
        end
      end

      class << self
        private
          def binary_path
            File.expand_path("../vendor/ejson", __dir__)
          end

          def decrypt_environment(ejson_path:, private_key: nil)
            with_secrets(ejson_path: ejson_path, private_key: private_key) do |path|
              output = %x(EJSON_KEYDIR=#{path} #{binary_path} decrypt #{ejson_path})
              JSON.parse(output)
            end
          end

          def with_secrets(ejson_path:, private_key: nil)
            raise MissingEjson unless File.exist?(ejson_path)

            content = File.read(ejson_path)
            ejson = JSON.parse(content)
            public_key = ejson["_public_key"]
            should_delete = false

            if !private_key.nil?
              secrets_path = Dir.mktmpdir
              should_delete = true
              File.write(File.join(secrets_path, public_key), private_key)
              yield(secrets_path)
            else
              yield("/opt/ejson/keys/")
            end
          ensure
            FileUtils.remove_dir(secrets_path, true) if should_delete
          end
      end
    end
  end
end
