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

    def okta_configured?
      okta_site = Environment.fetch(:okta, :site)
      okta_client_id = Environment.fetch(:okta, :client_id)
      okta_client_secret = Environment.fetch(:okta, :client_secret)
      return okta_site.present? && okta_client_id.present? && okta_client_secret.present?
    end

    def github_configured?
      github_oauth_id = Environment.fetch(:devise, :omniauth, :github, :oauth_id)
      github_oauth_secret = Environment.fetch(:devise, :omniauth, :github, :oauth_secret)
      return github_oauth_id.present? && github_oauth_secret.present?
    end

    def aws_configured?
      key_id = Environment.fetch(:aws, :access_key_id)
      key_secret = Environment.fetch(:aws, :access_key_secret)
      key_id.present? && key_secret.present?
    end

    def storage_configured?
      aws_configured?
    end

    def ensure_configured!
      return if Rails.env.test? || Rails.env.development?

      errors = []
      errors << "Storage is not configured" unless storage_configured?
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
