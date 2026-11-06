defmodule PulseWeb.PrometheusQueryController do
  @moduledoc "Prometheus-compatible instant and range queries over Pulse's stored metrics."
  use PulseWeb, :controller

  alias Pulse.Auth
  alias Pulse.PromQL.Evaluator
  alias Pulse.PromQL.Parser
  alias Pulse.PromQL.Time
  alias Pulse.QueryLimit
  alias PulseWeb.PrometheusLimit

  def query(conn, params), do: run(conn, params, :instant)
  def query_range(conn, params), do: run(conn, params, :range)

  defp run(conn, params, mode) do
    tenant =
      case get_req_header(conn, "x-scope-orgid") do
        [value | _] when value != "" -> value
        _ -> "default"
      end

    with :ok <- authorize(conn, tenant),
         :ok <- supported_parameters(params, mode),
         {:ok, limit} <- PrometheusLimit.parse(params["limit"]),
         query when is_binary(query) <- params["query"],
         {:ok, opts} <- options(params, mode),
         {:ok, opts} <- timeout_options(params, opts),
         {:ok, opts} <- lookback_options(params, opts),
         {:ok, result} <- Evaluator.query(query, tenant, opts) do
      json(conn, PrometheusLimit.response(result, limit))
    else
      {:error, :unauthorized} ->
        error(conn, :unauthorized, "unauthorized", "unauthorized")

      {:error, {:unauthorized, :forbidden}} ->
        error(conn, :forbidden, "forbidden", "forbidden")

      {:error, {:unauthorized, :auth_unavailable}} ->
        error(conn, :service_unavailable, "unavailable", "auth_unavailable")

      {:error, {:unauthorized, _}} ->
        error(conn, :unauthorized, "unauthorized", "unauthorized")

      {:error, {:invalid_parameter, message}} ->
        error(conn, :bad_request, "bad_data", message)

      {:error, {:invalid_label_replace_regex, regex}} when is_binary(regex) and byte_size(regex) <= 1024 ->
        error(conn, :bad_request, "bad_data", "invalid regular expression in label_replace(): " <> regex)

      {:error, :range_result_for_range_query} ->
        error(
          conn,
          :bad_request,
          "bad_data",
          "invalid parameter \"query\": query expression produces a range vector, but expression for range queries must produce an instant vector or scalar"
        )

      {:error, :query_execution_failed} ->
        error(conn, :internal_server_error, "execution", "Metric query execution failed.")

      {:error, :multiple_matches_for_labels} ->
        error(
          conn,
          :unprocessable_entity,
          "execution",
          "multiple matches for labels: grouping labels must ensure unique matches"
        )

      {:error, reason} when reason in [:many_to_many_matching, :duplicate_result_label_sets] ->
        error(conn, :unprocessable_entity, "execution", "Vector matching produced ambiguous or duplicate series.")

      {:error, {:invalid_ranking_parameter, op, :nan}} when op in ["topk", "bottomk"] ->
        error(conn, :unprocessable_entity, "execution", "parameter value is NaN for " <> op)

      {:error, :invalid_aggregation_parameter} ->
        error(
          conn,
          :unprocessable_entity,
          "execution",
          "Ranking requires a scalar other than NaN and below the signed int64 maximum."
        )

      {:error, {:invalid_smoothing_factor, name, value}} ->
        {factor, parameter} = if name == :smoothing, do: {"smoothing", "sf"}, else: {"trend", "tf"}

        value =
          if is_number(value),
            do: IO.iodata_to_binary(:io_lib.format(~c"~.6f", [value * 1.0])),
            else: Evaluator.format_value(value)

        error(
          conn,
          :unprocessable_entity,
          "execution",
          "invalid #{factor} factor. Expected: 0 < #{parameter} < 1, got: #{value}"
        )

      {:error, :query_overloaded} ->
        error(conn, :too_many_requests, "execution", "Query capacity is busy; retry later.")

      {:error, :invalid_stored_sample} ->
        error(conn, :internal_server_error, "execution", "Stored metric data contains an unsupported sample value.")

      {:error, {:storage_error, _}} ->
        error(conn, :service_unavailable, "execution", "Metric storage is unavailable.")

      {:error, reason}
      when reason in [
             :query_sample_limit,
             :query_scan_limit,
             :query_work_limit,
             :query_result_limit,
             :query_intermediate_limit,
             :query_resource_limit,
             :query_timeout
           ] ->
        # Name the limit and its value, so dashboards and agents can tell a
        # scan budget from a deadline. The limit also comes back structured.
        detail = QueryLimit.take()

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          "status" => "error",
          "errorType" => "execution",
          "error" => "query exceeded " <> (QueryLimit.describe(detail) || "its resource budget (#{reason})"),
          "limit" => QueryLimit.to_map(detail)
        })

      {:error, _} ->
        error(conn, :bad_request, "bad_data", "Invalid or unsupported query parameters.")

      _ ->
        error(conn, :bad_request, "bad_data", "query is required")
    end
  end

  defp supported_parameters(params, mode) do
    allowed = if mode == :instant, do: ["query", "time", "timeout"], else: ["query", "start", "end", "step", "timeout"]

    # Like Mimir, accept Prometheus' optional stats selector without inventing
    # JSON execution statistics. Grafana's query-statistics setting sends it
    # for both GET and form POST, including backend alert queries.
    if Enum.all?(Map.keys(params), &(&1 in ["limit", "stats", "lookback_delta" | allowed])) and
         (not Map.has_key?(params, "stats") or is_binary(params["stats"])),
       do: :ok,
       else: {:error, :unsupported_parameters}
  end

  defp lookback_options(params, opts) do
    case Map.fetch(params, "lookback_delta") do
      :error ->
        {:ok, opts}

      {:ok, value} ->
        case step(value) do
          {:ok, ns} when ns > 0 and ns <= 9_223_372_036_854_775_807 -> {:ok, Map.put(opts, :lookback_ns, ns)}
          _ -> {:error, :invalid_lookback}
        end
    end
  end

  defp timeout_options(params, opts) do
    case Map.fetch(params, "timeout") do
      :error ->
        {:ok, opts}

      {:ok, value} ->
        case step(value) do
          {:ok, ns} when ns > 0 -> {:ok, Map.put(opts, :timeout_ms, min(10_000, div(ns + 999_999, 1_000_000)))}
          _ -> {:error, :invalid_timeout}
        end
    end
  end

  defp authorize(conn, tenant) do
    case Auth.verify(conn, tenant, :read) do
      :ok -> :ok
      {:error, reason} -> {:error, {:unauthorized, reason}}
    end
  end

  defp options(params, :instant) do
    with {:ok, time} <- Time.parse_timestamp(Map.get(params, "time", System.system_time(:second))) do
      {:ok, %{end_ts_ns: time}}
    end
  end

  defp options(params, :range) do
    with {:ok, start} <- range_timestamp(params["start"], "start"),
         {:ok, finish} <- range_timestamp(params["end"], "end"),
         :ok <- range_order(start, finish),
         {:ok, step} <- range_step(params["step"]),
         :ok <- range_resolution(start, finish, step) do
      {:ok, %{start_ts_ns: start, end_ts_ns: finish, step_ns: step}}
    end
  end

  defp range_timestamp(value, field) do
    case Time.parse_timestamp(value) do
      {:ok, _} = result -> result
      _ -> invalid_parameter(field, "cannot parse #{diagnostic_value(value)} to a valid timestamp")
    end
  end

  defp range_order(start, finish) when start <= finish, do: :ok
  defp range_order(_, _), do: invalid_parameter("end", "end timestamp must not be before start time")

  defp range_step(value) do
    # Keep the exact existing parsers/precision. Numeric nonpositive values must
    # not fall through to the positive-only duration parser and lose their cause.
    parsed =
      case Time.parse_seconds(value) do
        {:ok, _} = result when is_binary(value) -> result
        _ -> step(value)
      end

    case parsed do
      {:ok, ns} when ns > 0 -> {:ok, ns}
      {:ok, _} -> nonpositive_step()
      _ -> invalid_duration_step(value)
    end
  end

  defp invalid_duration_step(value) do
    # The duration parser only returns positive values. Recognize its zero-unit
    # spelling for diagnostics, without admitting a new successful duration form.
    if is_binary(value) and byte_size(value) <= 128 and Regex.match?(~r/\A(?:0+(?:ms|s|m|h|d|w|y))+\z/, value) do
      nonpositive_step()
    else
      invalid_parameter("step", "cannot parse #{diagnostic_value(value)} to a valid duration")
    end
  end

  defp nonpositive_step do
    invalid_parameter(
      "step",
      "zero or negative query resolution step widths are not accepted. Try a positive integer"
    )
  end

  defp range_resolution(start, finish, step) do
    # Preserve the evaluator's inclusive 11,000-point ceiling, not upstream's
    # 11,000-interval check (which can admit an extra endpoint).
    if div(finish - start, step) < Pulse.QueryLimits.max_evaluation_steps() do
      :ok
    else
      {:error,
       {:invalid_parameter,
        "exceeded maximum resolution of 11,000 points per timeseries. Try decreasing the query resolution (?step=XX)"}}
    end
  end

  defp invalid_parameter(field, reason), do: {:error, {:invalid_parameter, "invalid parameter \"#{field}\": #{reason}"}}

  # Bound reflected bytes before Go quoting (including invalid UTF-8 and byte
  # cuts inside a scalar). Never inspect arbitrary nested request terms.
  defp diagnostic_value(value) when is_binary(value) and byte_size(value) > 128,
    do: Pulse.GoUnicode.quote(binary_part(value, 0, 128) <> "...(truncated)")

  defp diagnostic_value(value) when is_binary(value), do: Pulse.GoUnicode.quote(value)
  defp diagnostic_value(nil), do: Pulse.GoUnicode.quote("")
  defp diagnostic_value(_), do: "non-string value"

  defp step(value) when is_binary(value) do
    case Time.parse_seconds(value) do
      {:ok, ns} when ns > 0 -> {:ok, ns}
      _ -> Parser.parse_duration(value)
    end
  end

  defp step(_), do: {:error, :invalid_step}

  defp error(conn, status, type, message) do
    conn |> put_status(status) |> json(%{"status" => "error", "errorType" => type, "error" => message})
  end
end
