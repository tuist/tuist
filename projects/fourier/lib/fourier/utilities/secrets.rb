# frozen_string_literal: true

module Fourier
  module Utilities
    module Secrets
      class << self
        def decrypt
          EncryptedEnvironment.load_from_ejson(secrets_ejson_path, private_key: ENV["SECRET_KEY"])
        end

        def encrypt
          EncryptedEnvironment.load_from_ejson(secrets_ejson_path, private_key: ENV["SECRET_KEY"])
        end

        def secrets_ejson_path
          File.expand_path("../../../../../secrets.ejson", __dir__)
        end
      end
    end
  end
end
