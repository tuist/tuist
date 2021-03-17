# frozen_string_literal: true
require "encrypted/environment"

module Fourier
  module Utilities
    module Secrets
      def self.decrypt
        Encrypted::Environment.load_from_ejson(secrets_ejson_path, private_key: ENV["SECRET_KEY"])
      end

      def self.encrypt
        Encrypted::Environment.load_from_ejson(secrets_ejson_path, private_key: ENV["SECRET_KEY"])
      end

      def self.secrets_ejson_path
        File.expand_path("../../../../../secrets.ejson", __dir__)
      end
    end
  end
end
