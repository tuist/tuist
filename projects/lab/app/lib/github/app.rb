# frozen_string_literal: true
require "octokit"
require "jwt"
require "digest"
require "openssl"
require "securecompare"
require "base64"
require "dig_bang"

module GitHub
  class App
    Error = Class.new(StandardError)
    NonExistingInstallationOnRepositoryError = Class.new(Error)

    attr_reader :app_id, :app_name, :bot_login, :webhook_secret, :private_key, :oauth_id, :oauth_secret

    def initialize(app_id:, app_name:, bot_login:, webhook_secret:, private_key:, oauth_id:, oauth_secret:)
      @app_id = app_id
      @app_name = app_name
      @bot_login = bot_login
      @webhook_secret = webhook_secret
      @private_key = private_key
      @oauth_id = oauth_id
      @oauth_secret = oauth_secret
    end

    # Returns the URL the user can be forwarded to
    # @param [String] ID of the user or organization that is installing your GitHub App.
    # @param [Array<String>] The list of repositories the app should be installed into.
    # @return [String] The URL to redirect the user to.
    def install_url(target_id:, repository_ids: [])
      query = URI.encode_www_form(
        suggested_target_id: target_id,
        repository_ids: repository_ids
      )
      "https://github.com/apps/#{app_name}/installations/new/permissions?#{query}"
    end

    def verify_webhook_signature(signature:, message:)
      algorithm, signature = signature.split("=", 2)
      return false unless algorithm == "sha1"
      SecureCompare.secure_compare(signature, OpenSSL::HMAC.hexdigest(algorithm, webhook_secret, message))
    end

    def authenticated_client
      Octokit::Client.new(bearer_token: token)
    end

    def authenticated_client_for_repository(repository_full_name)
      cache_key = [self, "repository_token", private_key, repository_full_name]
      return Octokit::Client.new(bearer_token: Rails.cache.fetch(cache_key)) if Rails.cache.exist?(cache_key)

      installation_id = installation_for_repository(repository_full_name)[:id]
      response = authenticated_client.create_app_installation_access_token(installation_id,
        repositories: [repository_full_name.split("/").last])
      token = response[:token]
      expires_at = response[:expires_at]
      Rails.cache.write(cache_key, token, expires_in: expires_at)
      Octokit::Client.new(bearer_token: token)
    end

    class << self
      def tuist_lab
        @tuist_lab ||= GitHub::App.new(
          app_id: Rails.application.credentials.devise.dig!(:omniauth, :github, :app_id),
          app_name: Rails.application.credentials.devise.dig!(:omniauth, :github, :app_name),
          bot_login: Rails.application.credentials.devise.dig!(:omniauth, :github, :bot_login),
          webhook_secret: Rails.application.credentials.devise.dig!(:omniauth, :github, :webhook_secret),
          private_key: Base64.decode64(Rails.application.credentials.devise.dig!(:omniauth, :github,
            :private_key_base_64)),
          oauth_id: Rails.application.credentials.devise.dig!(:omniauth, :github, :client_id),
          oauth_secret: Rails.application.credentials.devise.dig!(:omniauth, :github, :client_secret)
        )
      end
    end

    private
      def installation_for_repository(repository_full_name)
        authenticated_client.find_repository_installation(repository_full_name)
      rescue Octokit::NotFound
        raise NonExistingInstallationOnRepositoryError
      end

      def token
        Rails.cache.fetch([self, private_key, app_id], expires_in: 10.minutes) do
          private_key = OpenSSL::PKey::RSA.new(self.private_key)
          payload = {
            # issued at time, 60 seconds in the past to allow for clock drift
            iat: Time.now.to_i - 60,
            exp: Time.now.to_i + (10 * 60),
            iss: app_id,
          }
          JWT.encode(payload, private_key, "RS256")
        end
      end
  end
end
