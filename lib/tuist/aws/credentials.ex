defmodule Tuist.AWS.Credentials do
  @moduledoc ~S"""
  This module provides utilities to interact with AWS credentials.
  """
  alias Tuist.Environment
  import SweetXml

  @cache_key "aws_token_file_credentials"

  def get_token_file_credentials(opts \\ []) do
    # Documentation: https://docs.aws.amazon.com/AWSJavaScriptSDK/v3/latest/Package/-aws-sdk-credential-providers/#fromtokenfile
    cache = Keyword.get(opts, :cache, :tuist)

    case Cachex.fetch(cache, @cache_key, fn ->
           ttl = Keyword.get(opts, :ttl, Environment.aws_token_file_credentials_ttl())
           {:commit, refresh_credentials_using_identity_token_file(ttl: ttl), ttl: ttl}
         end) do
      {:commit, credentials, _} -> credentials
      {:ok, credentials} -> credentials
    end
  end

  defp refresh_credentials_using_identity_token_file(opts) do
    if is_nil(Environment.aws_web_identity_token_file()) do
      nil
    else
      form = %{
        "Action" => "AssumeRoleWithWebIdentity",
        "RoleArn" => Environment.aws_role_arn(),
        "RoleSessionName" => Environment.aws_role_session_name(UUIDv7.generate()),
        "WebIdentityToken" => File.read!(Environment.aws_web_identity_token_file()),
        "Version" => "2006-03-01",
        "DurationSeconds" => trunc(Keyword.fetch!(opts, :ttl) / 1000)
      }

      headers = [{"Content-Type", "application/x-www-form-urlencoded"}]

      %{body: body} = Req.get!("https://sts.amazonaws.com/", form: form, headers: headers)

      %{
        access_key_id: body |> xpath(~x"//AccessKeyId/text()"),
        secret_access_key: body |> xpath(~x"//SecretAccessKey/text()"),
        session_token: body |> xpath(~x"//SessionToken/text()")
      }
    end
  end
end
