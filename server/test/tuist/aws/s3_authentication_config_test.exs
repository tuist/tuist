defmodule Tuist.AWS.S3AuthenticationConfigTest do
  use ExUnit.Case, async: true

  alias Tuist.AWS.S3AuthenticationConfig
  alias Tuist.Environment

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
               awscli_auth_adapter: ExAws.STS.AuthCache.AssumeRoleWebIdentityAdapter,
               region: Environment.s3_region(secrets)
             ]
    end

    test "ignores unsupported authentication methods" do
      assert S3AuthenticationConfig.ex_aws_config(:unsupported, %{}) == []
    end
  end
end
