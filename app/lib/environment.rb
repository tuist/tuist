# frozen_string_literal: true

module Environment
  TRUTHY_VALUES = %w[1 true TRUE yes YES].freeze
  FALSY_VALUES = %w[0 false FALSE no NO].freeze

  # Errors
  Error = Class.new(StandardError)
  KeyNotFoundError = Class.new(Error)

  class << self
    def self_hosted?(env: ENV)
      truthy?(env['TUIST_CLOUD_SELF_HOSTED'])
    end

    def tuist_hosted?(env: ENV)
      !self_hosted?(env: env)
    end

    def production_like_env?(env: ENV)
      (Rails.env.production? || Rails.env.staging? || Rails.env.canary?) && !precompiling_assets?(env: env)
    end

    def truthy?(value)
      return false if value.blank?

      TRUTHY_VALUES.any? { |v| v == value.to_s }
    end

    def falsy?(value)
      return true if value.blank?

      FALSY_VALUES.any? { |v| v == value.to_s }
    end

    def fetch(*args, env: ENV, credentials: Rails.application.credentials, defaults: Rails.application.config.defaults,
      with_prefix: true)
      env_variable_key = args.join('_').upcase.to_s
      env_variable_key = "TUIST_#{env_variable_key}" if with_prefix
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

    def database_url
      fetch(:database_url, with_prefix: false)
    end

    def aws_access_key_id
      fetch(:aws, :access_key_id)
    end

    def aws_secret_access_key
      fetch(:aws, :secret_access_key)
    end

    def aws_region
      fetch(:aws, :region)
    end

    def aws_endpoint
      fetch(:aws, :endpoint)
    end

    def aws_bucket_name
      fetch(:aws, :bucket_name)
    end

    def storage_configured?
      aws_configured?
    end

    def blocklisted_slug_keywords
      fetch(:blocklisted_slug_keywords)
    end

    def secret_key_tokens
      fetch(:secret_key, :tokens) || secret_key_base
    end

    def secret_key_password
      fetch(:secret_key, :password) || secret_key_base
    end

    def secret_key_base(env: ENV, credentials: Rails.application.credentials,
      defaults: Rails.application.config.defaults, with_prefix: true)
      fetch(:secret_key, :base, env: env, credentials: credentials, defaults: defaults, with_prefix: with_prefix)
    end

    def app_url
      fetch(:app_url)
    end

    def github_oauth_id
      fetch(:github, :oauth_id)
    end

    def github_oauth_secret
      fetch(:github, :oauth_secret)
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

    def attio_api_key
      fetch(:attio, :api_key)
    end

    def stripe_api_key
      fetch(:stripe, :secret_key)
    end

    def stripe_publishable_key
      fetch(:stripe, :publishable_key)
    end

    def stripe_endpoint_secret
      fetch(:stripe, :endpoint_secret)
    end

    def precompiling_assets?(env: ENV)
      truthy?(env['SECRET_KEY_BASE_DUMMY'])
    end

    def smpt_domain
      fetch(:smpt_settings, :domain)
    end

    def smpt_user_name
      fetch(:smpt_settings, :user_name)
    end

    def smpt_password
      fetch(:smpt_settings, :password)
    end

    # Configuration checkers

    def attio_configured?
      attio_api_key.present?
    end

    def stripe_configured?
      stripe_api_key.present? &&
        stripe_publishable_key.present? &&
        stripe_endpoint_secret.present?
    end

    def smpt_configured?
      smpt_domain.present? && smpt_user_name.present? && smpt_password.present?
    end

    def okta_configured?
      okta_site.present? && okta_client_id.present? && okta_client_secret.present?
    end

    def github_configured?
      github_oauth_id.present? && github_oauth_secret.present?
    end

    def aws_configured?
      aws_access_key_id.present? && aws_secret_access_key.present? && aws_region.present? &&
        (tuist_hosted? || aws_bucket_name.present?)
    end

    def app_url_configured?
      app_url.present?
    end

    def database_configured?
      database_url.present?
    end

    def secret_key_base_configured?
      secret_key_base.present?
    end

    def ensure_configured!
      return if Rails.env.test? || Rails.env.development? || precompiling_assets?

      errors = []
      errors << "Storage is not configured" unless storage_configured?
      errors << "Application URL is not configured" unless app_url_configured?
      errors << "Database is not configured" unless database_configured?
      errors << "Secret key base is not configured" unless secret_key_base_configured?
      unless Environment.self_hosted?
        errors << "Stripe is not configured" unless stripe_configured?
      end

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
