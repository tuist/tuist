defmodule Tuist.AWS.S3AuthenticationConfig do
  @moduledoc false

  alias Tuist.Environment

  @aws_web_identity_token_profile "tuist_web_identity_token"
  @aws_web_identity_token_refresh_interval_seconds 30

  def ex_aws_config(:env_access_key_id_and_secret_access_key, secrets) do
    [
      secret_access_key: Environment.s3_secret_access_key(secrets),
      access_key_id: Environment.s3_access_key_id(secrets)
    ]
  end

  def ex_aws_config(:aws_web_identity_token_from_env_vars, _secrets) do
    # ExAws runs the awscli provider before the STS adapter. The empty in-memory
    # profile keeps IRSA from depending on ~/.aws/config or configparser_ex.
    [
      secret_access_key: [{:awscli, @aws_web_identity_token_profile, @aws_web_identity_token_refresh_interval_seconds}],
      access_key_id: [{:awscli, @aws_web_identity_token_profile, @aws_web_identity_token_refresh_interval_seconds}],
      awscli_credentials: %{@aws_web_identity_token_profile => %{}},
      awscli_auth_adapter: ExAws.STS.AuthCache.AssumeRoleWebIdentityAdapter
    ]
  end

  def ex_aws_config(_authentication_method, _secrets), do: []
end
