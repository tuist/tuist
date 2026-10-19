defmodule TuistEx.Analytics.HTTP do
  @moduledoc false

  alias TuistEx.Analytics.Actor
  alias TuistEx.Analytics.Config
  alias TuistEx.Analytics.Report
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
  # `POST /api/projects/:account/:project/mix/builds`. Older schema/context
  # validators reject up_to_date observations; retry once without those only.
  def submit_mix_build(payload, options \\ []) do
    case post_analytics(payload, "/mix/builds", options) do
      {:error, {:http, 400, %{"message" => message}}} = error when is_binary(message) ->
        legacy = without_current_hits(payload)

        if legacy != payload and
             (message == "The dependency cache data is invalid." or
                "Invalid value for enum" in String.split(message, "\n")) do
          Report.debug(
            "tuist analytics: retrying compile report without up-to-date cache observations"
          )

          post_analytics(legacy, "/mix/builds", options)
        else
          error
        end

      result ->
        result
    end
  end

  defp without_current_hits(payload) when is_map(payload) do
    Enum.reduce([:dependency_cache, "dependency_cache"], payload, fn key, payload ->
      case Map.get(payload, key) do
        events when is_list(events) ->
          Map.put(payload, key, Enum.reject(events, &current_hit?/1))

        _ ->
          payload
      end
    end)
  end

  defp without_current_hits(payload), do: payload

  defp current_hit?(event) when is_map(event) do
    Map.get(event, :reason, Map.get(event, "reason")) == "up_to_date" and
      Map.get(event, :outcome, Map.get(event, "outcome")) == "local_hit"
  end

  defp current_hit?(_event), do: false

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
