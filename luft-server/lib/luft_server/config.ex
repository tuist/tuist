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

  @doc "The OAuth client for ChatGPT subscription sign-in; ChatGPT can't connect without it."
  def chatgpt_client_id, do: Application.get_env(:luft_server, :chatgpt_client_id)

  @doc "Extra Req options for requests to OpenAI (tests route them to `Req.Test`)."
  def openai_req_options, do: Application.get_env(:luft_server, :openai_req_options, [])

  def cache_provider_metadata?,
    do: Application.get_env(:luft_server, :cache_provider_metadata, true)
end
