# frozen_string_literal: true

module Environment
  TRUTHY_VALUES = %w[1 true TRUE yes YES].freeze

  # Errors
  Error = Class.new(StandardError)
  KeyNotFoundError = Class.new(Error)

  class << self
    def self_hosted?(env: ENV)
      truthy?(env['TUIST_CLOUD_SELF_HOSTED'])
    end

    def fetch(*args, env: ENV)
      key = "TUIST_#{args.join('_').upcase}"
      env.to_h.fetch(key, nil)
    end

    def truthy?(value)
      return false if value.blank?

      TRUTHY_VALUES.any? { |v| v == value.to_s }
    end

    def fetch(*args, env: ENV, credentials: Rails.application.credentials, defaults: Rails.application.config.defaults)
      env_variable_key = "TUIST_#{args.join('_').upcase}"
      env_variable_value = env.to_h.fetch(env_variable_key, nil)
      credentials_value = credentials.dig(*args)
      defaults_value = defaults.dig(*args)
      env_variable_value || credentials_value || defaults_value
    end

    def fetch!(*args, env: ENV, credentials: Rails.application.credentials, defaults: Rails.application.config.defaults)
      value = fetch(*args, env:, credentials:, defaults:)
      if value.blank?
        raise KeyNotFoundError, "The key #{args.map(&:to_s).join('.')} was not found in the app credentials"
      end

      value
    end

    # Getters

    def aws_access_key_id
      fetch(:aws, :access_key_id)
    end

    def aws_access_key_secret
      fetch(:aws, :access_key_secret)
    end

    def storage_configured?
      aws_configured?
    end

    def blocklisted_slug_keywords
      fetch(:blocklisted_slug_keywords)
    end

    def tokens_secret_key
      fetch(:devise, :secret_key)
    end

    def password_pepper
      fetch(:devise, :pepper)
    end

    def secret_key_base
      fetch(:secret_key_base)
    end

    def app_url
      fetch(:app_url)
    end

    def github_oauth_id
      fetch(:devise, :omniauth, :github, :oauth_id)
    end

    def github_oauth_secret
      fetch(:devise, :omniauth, :github, :oauth_secret)
    end

    def okta_site
      fetch(:okta, :site)
    end

    def okta_client_id
      fetch(:okta, :client_id)
    end

    def okta_client_secret
      fetch(:okta, :client_secret)
    end

    def okta_authorize_url
      fetch(:okta, :authorize_url)
    end

    def okta_token_url
      fetch(:okta, :token_url)
    end

    def okta_user_info_url
      fetch(:okta, :user_info_url)
    end

    # Configuration checkers

    def okta_configured?
      okta_site = fetch(:okta, :site)
      okta_client_id = fetch(:okta, :client_id)
      okta_client_secret = fetch(:okta, :client_secret)
      return okta_site.present? && okta_client_id.present? && okta_client_secret.present?
    end

    def github_configured?
      github_oauth_id = fetch(:devise, :omniauth, :github, :oauth_id)
      github_oauth_secret = fetch(:devise, :omniauth, :github, :oauth_secret)
      return github_oauth_id.present? && github_oauth_secret.present?
    end

    def aws_configured?
      key_id = aws_access_key_id
      key_secret = aws_access_key_secret
      key_id.present? && key_secret.present?
    end

    def app_url_configured?
      app_url.present?
    end

    def ensure_configured!
      return if Rails.env.test? || Rails.env.development?

      errors = []
      errors << "Storage is not configured" unless storage_configured?
      errors << "Application URL is not configured" unless app_url_configured?

      if errors.any?
        raise Error, <<~ERROR
        Can't start Tuist Cloud due to the following errors:
        #{errors.map { |error| " - #{error}" }.join("\n")}

        Please, check our documentation to learn how to configure Tuist Cloud: https://github.com/tuist/cloud-enterprise
        ERROR
      end
    end

  end
end
