defmodule TuistCloud.Environment do
  @moduledoc false
  @env Mix.env()

  defmodule Version do
    @moduledoc ~S"""
    A module that represents a Tuist Cloud version.
    Tuist Cloud versions follow the convention MAJOR.YY.MM.DD.
    """
    @type t :: %{
            major: integer(),
            date: Date.t()
          }
    @enforce_keys [:major, :date]

    defstruct [:major, :date]
  end

  def env, do: @env

  def truthy?(value) do
    ["1", "true", "TRUE", "yes", "YES"] |> Enum.member?(value)
  end

  def on_premise?() do
    not truthy?(System.get_env("TUIST_CLOUD_HOSTED", "0"))
  end

  def use_ssl_for_database?() do
    truthy?(System.get_env("TUIST_USE_SSL_FOR_DATABASE", "1"))
  end

  def license_features() do
    Application.get_env(:tuist_cloud, :license).features
  end

  def analytics_enabled?() do
    !on_premise?() and env() == :prod
  end

  def license_expiration_date() do
    {:ok, expiration_date} =
      Date.from_iso8601(Application.get_env(:tuist_cloud, :license).expiration_date)

    expiration_date
  end

  def license_expired?() do
    TuistCloud.Native.License.expired?(Application.get_env(:tuist_cloud, :license))
  end

  def license_expiration_days_span() do
    Date.diff(license_expiration_date(), Date.utc_today())
  end

  def version() do
    version = get([:version])

    case version do
      nil ->
        %Version{major: "1", date: Date.utc_today()}

      "" ->
        %Version{major: "1", date: Date.utc_today()}

      version ->
        [major, yy, mm, dd] = String.split(version, ".")

        date =
          Date.from_iso8601("#{yy}-#{mm}-#{dd}")
          |> case do
            {:ok, date} -> date
            # Fallback in case of error
            {:error, _} -> Date.utc_today()
          end

        %Version{major: major, date: date}
    end
  end

  def secret_key_base(secrets \\ secrets()) do
    get([:secret_key, :base], secrets)
  end

  def attio_api_key(secrets \\ secrets()) do
    get([:attio, :api_key], secrets)
  end

  def posthog_api_key(secrets \\ secrets()) do
    get([:posthog, :api_key], secrets)
  end

  def posthog_url(secrets \\ secrets()) do
    get([:posthog, :url], secrets)
  end

  def s3_access_key_id(secrets \\ secrets()) do
    System.get_env("AWS_ACCESS_KEY_ID") || get([:aws, :access_key_id], secrets) ||
      get([:s3, :access_key_id], secrets)
  end

  def s3_secret_access_key(secrets \\ secrets()) do
    System.get_env("AWS_SECRET_ACCESS_KEY") || get([:aws, :secret_access_key], secrets) ||
      get([:s3, :secret_access_key], secrets)
  end

  def aws_region(secrets \\ secrets()) do
    System.get_env("AWS_REGION") || get([:aws, :region], secrets) || "auto"
  end

  def aws_session_token(secrets \\ secrets()) do
    System.get_env("AWS_SESSION_TOKEN") || get([:aws, :session_token], secrets)
  end

  def aws_profile(secrets \\ secrets()) do
    System.get_env("AWS_PROFILE") || get([:aws, :profile], secrets) || :system
  end

  def aws_use_session_token?(secrets \\ secrets()) do
    get([:aws, :use_session_token], secrets) || :system
  end

  def s3_region(secrets \\ secrets()) do
    get([:aws, :region], secrets) || get([:s3, :region], secrets)
  end

  def s3_bucket_name(secrets \\ secrets()) do
    get([:aws, :bucket_name], secrets) || get([:s3, :bucket_name], secrets)
  end

  def s3_endpoint(secrets \\ secrets()) do
    get([:aws, :endpoint], secrets) || get([:s3, :endpoint], secrets)
  end

  def s3_configured?(secrets \\ secrets()) do
    s3_access_key_id(secrets) != nil and s3_secret_access_key(secrets) != nil and
      s3_region(secrets) != nil and
      (!on_premise?() or s3_bucket_name(secrets) != nil)
  end

  def stripe_api_key(secrets \\ secrets()) do
    get([:stripe, :secret_key], secrets)
  end

  def stripe_publishable_key(secrets \\ secrets()) do
    get([:stripe, :publishable_key], secrets)
  end

  def stripe_endpoint_secret(secrets \\ secrets()) do
    get([:stripe, :endpoint_secret], secrets)
  end

  def stripe_configured?(secrets \\ secrets()) do
    stripe_api_key(secrets) != nil and stripe_publishable_key(secrets) != nil and
      stripe_endpoint_secret(secrets) != nil
  end

  def github_oauth_id(secrets \\ secrets()) do
    get([:github, :oauth_id], secrets)
  end

  def github_oauth_secret(secrets \\ secrets()) do
    get([:github, :oauth_secret], secrets)
  end

  def github_configured?(secrets \\ secrets()) do
    github_oauth_id(secrets) != nil and github_oauth_secret(secrets) != nil
  end

  def google_oauth_client_id(secrets \\ secrets()) do
    get([:google, :oauth_client_id], secrets)
  end

  def google_oauth_client_secret(secrets \\ secrets()) do
    get([:google, :oauth_client_secret], secrets)
  end

  def google_oauth_configured?(secrets \\ secrets()) do
    google_oauth_client_id(secrets) != nil and google_oauth_client_secret(secrets) != nil
  end

  def okta_site(secrets \\ secrets()) do
    get([:okta, :site], secrets)
  end

  def okta_client_secret(secrets \\ secrets()) do
    get([:okta, :client_secret], secrets)
  end

  def okta_authorize_url(secrets \\ secrets()) do
    get([:okta, :authorize_url], secrets)
  end

  def okta_token_url(secrets \\ secrets()) do
    get([:okta, :token_url], secrets)
  end

  def okta_user_info_url(secrets \\ secrets()) do
    get([:okta, :user_info_url], secrets)
  end

  def okta_event_hook_secret(secrets \\ secrets()) do
    get([:okta, :event_hook_secret], secrets)
  end

  def okta_configured?(secrets \\ secrets()) do
    okta_site(secrets) != nil and okta_client_secret(secrets) != nil and
      okta_authorize_url(secrets) != nil and okta_token_url(secrets) != nil and
      okta_user_info_url(secrets) != nil and okta_event_hook_secret(secrets) != nil and
      okta_event_hook_secret(secrets) != nil
  end

  def smtp_domain(secrets \\ secrets()) do
    get([:smtp_settings, :domain], secrets)
  end

  def smtp_user_name(secrets \\ secrets()) do
    get([:smtp_settings, :user_name], secrets)
  end

  def smtp_password(secrets \\ secrets()) do
    get([:smtp_settings, :password], secrets)
  end

  def smtp_configured?(secrets \\ secrets()) do
    smtp_domain(secrets) != nil and smtp_user_name(secrets) != nil and
      smtp_password(secrets) != nil
  end

  def app_signal_push_api_key(secrets \\ secrets()) do
    get([:app_signal, :push_api_key], secrets)
  end

  def secret_key_password(secrets \\ secrets()) do
    get([:secret_key, :password], secrets)
  end

  def get(keys, secrets \\ secrets()) do
    env_variable =
      "TUIST_#{keys |> Enum.map(&Atom.to_string/1) |> Enum.map_join("_", &String.upcase/1)}"

    if System.get_env(env_variable) do
      System.get_env(env_variable)
    else
      get_in(secrets, keys)
    end
  end

  def secrets do
    Application.get_env(:tuist_cloud, :secrets)[env()] || %{}
  end

  def put_application_secrets(secrets) do
    Application.put_env(:tuist_cloud, :secrets, secrets)
    :ok
  end

  @doc ~s"""
  It decrypts the secrets and returns them.
  """
  def decrypt_secrets() do
    master_key_path = Path.join("priv/secrets", "master.key")
    master_key_env_variable = "PHX_MASTER_KEY"
    secrets_path = System.get_env("SECRETS_PATH", "priv/secrets//secrets.yml.enc")

    if System.get_env(master_key_env_variable) || File.exists?(master_key_path) do
      key = System.get_env(master_key_env_variable) || File.read!(master_key_path)
      EncryptedSecrets.read!(key, secrets_path)
    else
      %{}
    end
  end
end
