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

  @doc """
  Calls a project endpoint, `/api/projects/:account/:project` followed by
  `suffix`, and returns `{:ok, decoded_body}` on 2xx.
  """
  def project_request(method, suffix, body, options) do
    with {:ok, config} <- Config.resolve(options),
         {:ok, token} <- Auth.token(options) do
      url =
        config.url <>
          "/api/projects/" <>
          config.project_handle.account <> "/" <> config.project_handle.project <> suffix

      case HTTP.request(method, url, body, [{"authorization", "Bearer " <> token}]) do
        {:ok, status, decoded} when status in 200..299 -> {:ok, decoded}
        {:ok, status, decoded} -> {:error, {:http, status, decoded}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp post_analytics(payload, suffix, options) do
    with {:ok, _body} <- project_request(:post, suffix, payload, options), do: :ok
  end
end
