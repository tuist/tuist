defmodule Tuist.OAuth2.SSOClient do
  @moduledoc ~S"""
  HTTP client for SSO OAuth2 token exchange and userinfo retrieval.

  Tuist-hosted deployments use Req/Finch with SSRF-safe pinned URLs via
  `SSRFGuard.pin/1`. Self-hosted deployments call the configured URL directly
  because the operator controls the private network the server runs in.
  """

  alias Tuist.Environment
  alias Tuist.OAuth2.SSRFGuard

  def exchange_token(token_url, code, redirect_uri, client_id, client_secret) do
    with {:ok, request_url, request_options} <- request_url_and_options(token_url) do
      body =
        URI.encode_query(%{
          grant_type: "authorization_code",
          code: code,
          redirect_uri: redirect_uri
        })

      request_options =
        Keyword.merge(request_options,
          body: body,
          headers: [
            {"content-type", "application/x-www-form-urlencoded"},
            {"accept", "application/json"},
            {"authorization", "Basic " <> Base.encode64("#{client_id}:#{client_secret}")}
          ],
          decode_body: false
        )

      case Req.post(request_url, request_options) do
        {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
          {:ok, decode_json(body)}

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, {:token_exchange_failed, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def fetch_userinfo(user_info_url, access_token) do
    with {:ok, request_url, request_options} <- request_url_and_options(user_info_url) do
      request_options =
        Keyword.merge(request_options,
          headers: [
            {"authorization", "Bearer #{access_token}"},
            {"accept", "application/json"}
          ],
          decode_body: false
        )

      case Req.get(request_url, request_options) do
        {:ok, %Req.Response{status: 200, body: body}} ->
          {:ok, decode_json(body)}

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, {:userinfo_request_failed, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp request_url_and_options(url) do
    if Environment.tuist_hosted?() do
      with {:ok, pinned_url, hostname} <- SSRFGuard.pin(url) do
        {:ok, pinned_url, connect_options: SSRFGuard.connect_options(hostname)}
      end
    else
      {:ok, url, []}
    end
  end

  defp decode_json(body) when is_binary(body) do
    case JSON.decode(body) do
      {:ok, decoded} -> decoded
      {:error, _} -> body
    end
  end

  defp decode_json(body), do: body
end
