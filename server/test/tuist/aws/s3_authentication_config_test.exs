defmodule Tuist.AWS.S3AuthenticationConfigTest do
  use ExUnit.Case, async: true

  alias ExAws.STS.AuthCache.AssumeRoleWebIdentityAdapter
  alias Tuist.AWS.S3AuthenticationConfig
  alias Tuist.Environment
  alias TuistCommon.AWS.CredentialFiles

  describe "ex_aws_config/2" do
    test "uses access key credentials" do
      secrets = %{
        "s3" => %{
          "access_key_id" => "access-key-id",
          "secret_access_key" => "secret-access-key"
        }
      }

      assert S3AuthenticationConfig.ex_aws_config(:env_access_key_id_and_secret_access_key, secrets) == [
               secret_access_key: "secret-access-key",
               access_key_id: "access-key-id"
             ]
    end

    test "uses an in-memory awscli profile for web identity token credentials" do
      secrets = %{"s3" => %{"region" => "eu-west-1"}}

      assert S3AuthenticationConfig.ex_aws_config(:aws_web_identity_token_from_env_vars, secrets) == [
               secret_access_key: [{:awscli, "tuist_web_identity_token", 30}],
               access_key_id: [{:awscli, "tuist_web_identity_token", 30}],
               awscli_credentials: %{"tuist_web_identity_token" => %{}},
               awscli_auth_adapter: AssumeRoleWebIdentityAdapter,
               region: Environment.s3_region(secrets)
             ]
    end

    @tag :tmp_dir
    test "reads the platform key from files through a refreshed profile", %{tmp_dir: dir} do
      File.write!(Path.join(dir, "access_key_id"), "KEY")
      File.write!(Path.join(dir, "secret_access_key"), "secret")
      secrets = %{"s3" => %{"credentials_dir" => dir}}

      assert S3AuthenticationConfig.ex_aws_config(:credential_files, secrets) == [
               secret_access_key: [{:awscli, "tuist_s3", 30}],
               access_key_id: [{:awscli, "tuist_s3", 30}],
               awscli_credentials: %{"tuist_s3" => %{credentials_dir: dir}},
               awscli_auth_adapter: CredentialFiles
             ]
    end

    test "refuses credential files without a directory" do
      assert_raise RuntimeError, ~r/TUIST_S3_CREDENTIALS_DIR/, fn ->
        S3AuthenticationConfig.ex_aws_config(:credential_files, %{})
      end
    end

    @tag :tmp_dir
    test "keeps web identity working next to a registry key read from files", %{tmp_dir: dir} do
      File.write!(Path.join(dir, "access_key_id"), "KEY")
      File.write!(Path.join(dir, "secret_access_key"), "secret")
      registry = %{"tuist_registry_s3" => %{credentials_dir: dir}}

      config = S3AuthenticationConfig.ex_aws_config(:aws_web_identity_token_from_env_vars, %{}, registry)

      assert config[:access_key_id] == [{:awscli, "tuist_web_identity_token", 30}]
      assert config[:awscli_auth_adapter] == CredentialFiles

      assert config[:awscli_credentials] == %{
               "tuist_web_identity_token" => %{delegate: AssumeRoleWebIdentityAdapter},
               "tuist_registry_s3" => %{credentials_dir: dir}
             }
    end

    test "ignores unsupported authentication methods" do
      assert S3AuthenticationConfig.ex_aws_config(:unsupported, %{}) == []
    end
  end
end
