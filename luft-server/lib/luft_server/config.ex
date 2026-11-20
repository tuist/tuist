defmodule LuftServer.Config do
  @moduledoc "Runtime configuration, read from the `:luft_server` application environment."

  def tuist_issuer,
    do: :luft_server |> Application.fetch_env!(:tuist_issuer) |> String.trim_trailing("/")

  def oauth_client_id, do: Application.fetch_env!(:luft_server, :oauth_client_id)
  def oauth_client_secret, do: Application.fetch_env!(:luft_server, :oauth_client_secret)

  def public_url,
    do: :luft_server |> Application.fetch_env!(:public_url) |> String.trim_trailing("/")

  def redirect_uri, do: public_url() <> "/auth/callback"

  def req_options, do: Application.get_env(:luft_server, :req_options, [])

  def cache_provider_metadata?,
    do: Application.get_env(:luft_server, :cache_provider_metadata, true)
end
