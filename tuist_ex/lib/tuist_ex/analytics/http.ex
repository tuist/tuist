defmodule TuistEx.Analytics.HTTP do
  @moduledoc false

  alias TuistEx.Analytics.Config
  alias TuistEx.Auth
  alias TuistEx.HTTP

  # Sends a fully-shaped test-run payload to
  # `POST /api/projects/:account/:project/tests`.
  #
  # Returns `:ok` on 2xx and `{:error, reason}` otherwise. Callers should not
  # let a submission failure change the exit code of `mix test`; analytics
  # ingest never determines a build's outcome.
  def submit_test_run(payload, options \\ []), do: post_analytics(payload, "/tests", options)

  # Sends a compile-run payload to
  # `POST /api/projects/:account/:project/mix/builds`.
  def submit_mix_build(payload, options \\ []),
    do: post_analytics(payload, "/mix/builds", options)

  defp post_analytics(payload, suffix, options) do
    with {:ok, config} <- Config.resolve(options),
         {:ok, token} <- Auth.token(options) do
      url =
        config.url <>
          "/api/projects/" <>
          config.project_handle.account <> "/" <> config.project_handle.project <> suffix

      headers = [{"authorization", "Bearer " <> token}]

      case HTTP.request(:post, url, payload, headers) do
        {:ok, status, _body} when status in 200..299 ->
          :ok

        {:ok, status, body} ->
          {:error, {:http, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
