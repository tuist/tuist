defmodule Tuist.AWS.S3AuthenticationConfig do
  @moduledoc false

  alias ExAws.STS.AuthCache.AssumeRoleWebIdentityAdapter
  alias Tuist.Environment
  alias TuistCommon.AWS.CredentialFiles

  @aws_web_identity_token_profile "tuist_web_identity_token"
  @aws_web_identity_token_refresh_interval_seconds 30
  @credential_files_profile "tuist_s3"
  @registry_credential_files_profile "tuist_registry_s3"

  @doc """
  The ExAws profile the registry bucket's key is read through when it comes
  from files (`TUIST_REGISTRY_S3_CREDENTIALS_DIR`).
  """
  def registry_credential_files_profile, do: @registry_credential_files_profile

  @doc """
  The top-level `:ex_aws` config for the platform storage's authentication
  method. `file_profiles` are other credential-file profiles the node needs,
  such as the registry bucket's: ExAws takes one auth adapter and one profile
  map per node, so they are configured together.
  """
  def ex_aws_config(authentication_method, secrets, file_profiles \\ %{})

  def ex_aws_config(:env_access_key_id_and_secret_access_key, secrets, file_profiles) do
    [
      secret_access_key: Environment.s3_secret_access_key(secrets),
      access_key_id: Environment.s3_access_key_id(secrets)
    ] ++ file_profiles_config(file_profiles)
  end

  def ex_aws_config(:aws_web_identity_token_from_env_vars, secrets, file_profiles) do
    credential = [{:awscli, @aws_web_identity_token_profile, @aws_web_identity_token_refresh_interval_seconds}]

    # ExAws runs the awscli provider before the STS adapter. The empty in-memory
    # profile keeps IRSA from depending on ~/.aws/config or configparser_ex.
    auth_config =
      if file_profiles == %{} do
        [
          awscli_credentials: %{@aws_web_identity_token_profile => %{}},
          awscli_auth_adapter: AssumeRoleWebIdentityAdapter
        ]
      else
        file_profiles
        |> Map.put(@aws_web_identity_token_profile, %{delegate: AssumeRoleWebIdentityAdapter})
        |> CredentialFiles.ex_aws_config()
      end

    [secret_access_key: credential, access_key_id: credential] ++
      auth_config ++ [region: Environment.s3_region(secrets)]
  end

  def ex_aws_config(:credential_files, secrets, file_profiles) do
    dir =
      Environment.s3_credentials_dir(secrets) ||
        raise "TUIST_S3_AUTHENTICATION_METHOD=credential_files requires TUIST_S3_CREDENTIALS_DIR"

    credential = CredentialFiles.credential(@credential_files_profile)

    [secret_access_key: credential, access_key_id: credential] ++
      CredentialFiles.ex_aws_config(Map.put(file_profiles, @credential_files_profile, %{credentials_dir: dir}))
  end

  def ex_aws_config(_authentication_method, _secrets, file_profiles), do: file_profiles_config(file_profiles)

  defp file_profiles_config(file_profiles) when file_profiles == %{}, do: []
  defp file_profiles_config(file_profiles), do: CredentialFiles.ex_aws_config(file_profiles)
end
