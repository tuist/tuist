# frozen_string_literal: true

require "google/cloud/storage"

module Fourier
  module Utilities
    class GoogleCloudStorage
      def self.new(environment: ENV)
        Google::Cloud::Storage.new(
          project_id: ENV["GCS_PROJECT_ID"],
          credentials: {
            type: ENV["GCS_TYPE"],
            project_id: ENV["GCS_PROJECT_ID"],
            private_key_id: ENV["GCS_PRIVATE_KEY_ID"],
            private_key: ENV["GCS_PRIVATE_KEY"],
            client_email: ENV["GCS_CLIENT_EMAIL"],
            client_id: ENV["GCS_CLIENT_ID"],
            auth_uri: ENV["GCS_AUTH_URI"],
            token_uri: ENV["GCS_TOKEN_URI"],
            auth_provider_x509_cert_url: ENV["GCS_AUTH_PROVIDER_X509_CERT_URL"],
            client_x509_cert_url: ENV["GCS_CLIENT_X509_CERT_URL"],
          }
        )
      end
    end
  end
end
