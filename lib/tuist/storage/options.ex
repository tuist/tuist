defmodule Tuist.Storage.Options do
  @moduledoc ~S"""
  A module to read the configuration to use for storage operations.
  """
  alias Tuist.Environment

  def get() do
    %{host: s3_endpoint_host} = Environment.s3_endpoint() |> URI.parse()

    options = [
      access_key_id: get_access_key_id(),
      secret_access_key: get_secret_access_key(),
      scheme: "https://",
      host: s3_endpoint_host,
      region: Environment.aws_region()
    ]

    session_token = get_session_token()

    if is_nil(session_token) do
      options
    else
      options |> Keyword.merge(session_token: session_token)
    end
  end

  defp get_session_token() do
    cond do
      Environment.aws_use_session_token?() ->
        Environment.aws_session_token()

      not is_nil(Tuist.AWS.Credentials.get_token_file_credentials()) ->
        Tuist.AWS.Credentials.get_token_file_credentials().session_token

      true ->
        nil
    end
  end

  defp get_access_key_id() do
    if is_nil(Tuist.AWS.Credentials.get_token_file_credentials()) do
      Environment.s3_access_key_id()
    else
      Tuist.AWS.Credentials.get_token_file_credentials().access_key_id
    end
  end

  defp get_secret_access_key() do
    if is_nil(Tuist.AWS.Credentials.get_token_file_credentials()) do
      Environment.s3_secret_access_key()
    else
      Tuist.AWS.Credentials.get_token_file_credentials().secret_access_key
    end
  end
end
