defmodule Tuist.OAuth2.SSOClient do
  @moduledoc ~S"""
  HTTP client for SSO OAuth2 token exchange and userinfo retrieval.

  Uses Req/Finch with SSRF-safe pinned URLs via `SSRFGuard.pin/1`.
  Each request is made against a pre-resolved public IP with Mint's
  `:hostname` connect option preserving TLS SNI + cert validation for
  the original hostname.
  """

  alias Tuist.OAuth2.SSRFGuard

  def exchange_token(token_url, code, redirect_uri, client_id, client_secret) do
    with {:ok, pinned_url, hostname} <- SSRFGuard.pin(token_url) do
      body =
        URI.encode_query(%{
          grant_type: "authorization_code",
          code: code,
          redirect_uri: redirect_uri
        })

      case Req.post(pinned_url,
             body: body,
             headers: [
               {"content-type", "application/x-www-form-urlencoded"},
               {"accept", "application/json"},
               {"authorization", "Basic " <> Base.encode64("#{client_id}:#{client_secret}")}
             ],
             connect_options: SSRFGuard.connect_options(hostname),
             decode_body: false
           ) do
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
    with {:ok, pinned_url, hostname} <- SSRFGuard.pin(user_info_url) do
      case Req.get(pinned_url,
             headers: [
               {"authorization", "Bearer #{access_token}"},
               {"accept", "application/json"}
             ],
             connect_options: SSRFGuard.connect_options(hostname),
             decode_body: false
           ) do
        {:ok, %Req.Response{status: 200, body: body}} ->
          {:ok, decode_json(body)}

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, {:userinfo_request_failed, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
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
