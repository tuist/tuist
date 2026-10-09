defmodule TuistEx.Analytics.HTTP do
  @moduledoc false

  alias TuistEx.Analytics.Actor
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
    report? = method == :post and suffix in ["/tests", "/mix/builds"]

    with {:ok, config} <- Config.resolve(options),
         {:ok, token} <- if(report?, do: Auth.reporting_token(options), else: Auth.token(options)) do
      body = if report? and is_nil(token), do: report_body(body), else: body

      url =
        config.url <>
          "/api/projects/" <>
          config.project_handle.account <> "/" <> config.project_handle.project <> suffix

      actor_headers =
        if report?,
          do: Actor.headers(options),
          else: []

      case HTTP.request(
             method,
             url,
             body,
             if(token, do: [{"authorization", "Bearer " <> token}], else: []) ++ actor_headers
           ) do
        {:ok, status, decoded} when status in 200..299 -> {:ok, decoded}
        {:ok, status, decoded} -> {:error, {:http, status, decoded}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp report_body(body) when is_map(body) do
    keys = ~w(generation_id build_run_id gradle_build_id shard_plan_id shard_index coverage
              xcode_coverage xcode_coverage_storage_key git_history stress_new_tests
              git_remote_url_origin coverage_evidence enumerated_tests changed_files base_branch
              merge_base_sha is_pull_request pull_request_number git_object_format history_source
              history_fallback_reason git_dirty only_test_identifiers skip_test_identifiers)a
    Map.drop(body, keys ++ Enum.map(keys, &Atom.to_string/1))
  end

  defp report_body(body), do: body

  defp post_analytics(payload, suffix, options) do
    with {:ok, _body} <- project_request(:post, suffix, payload, options), do: :ok
  end
end
