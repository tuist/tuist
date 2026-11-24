defmodule Tuist.Pulse.Errors do
  @moduledoc """
  Issue reads over Pulse's `errors` table, one row per Sentry event.

  Rows are written by the `sentry_errors` pipeline
  (`infra/helm/pulse/sentry-errors.yaml`), which computes Atlas's
  fingerprint and scrubs each event before storage. An issue is
  `(service, fingerprint)`; its title, culprit, level, platform and
  environment are those of its latest event in the window, and `environments`
  counts the distinct environments it occurred in. Timestamps are Unix nanoseconds as strings,
  like logs and traces. Occurrence series divide the window into 60 equal
  buckets labelled by their start in Unix seconds.

  The table is append-only, so an SDK's resend of an event is a second row
  with the same `event_id`: counts are of distinct event IDs, and event lists
  show each resent row once.
  """

  import Tuist.Pulse.SQL, only: [bounds: 2, literal: 1, sql: 2]

  @issue_columns "service, fingerprint, count(DISTINCT event_id) AS events, " <>
                   "count(DISTINCT nullif(account_handle, '')) AS accounts, " <>
                   "arrow_cast(min(timestamp), 'Int64') AS first_seen, " <>
                   "arrow_cast(max(timestamp), 'Int64') AS last_seen, " <>
                   ~s|last_value(title ORDER BY timestamp) AS title, | <>
                   ~s|last_value(culprit ORDER BY timestamp) AS culprit, | <>
                   ~s|last_value("level" ORDER BY timestamp) AS "level", | <>
                   ~s|last_value(platform ORDER BY timestamp) AS platform, | <>
                   ~s|last_value(environment ORDER BY timestamp) AS environment, | <>
                   "count(DISTINCT nullif(environment, '')) AS environments, " <>
                   ~s|last_value(event_id ORDER BY timestamp) AS latest_event_id|

  @event_columns ~s|arrow_cast(timestamp, 'Int64') AS timestamp, event_id, title, "level", environment, "release", | <>
                   ~s|server_name, trace_id, account_handle, sdk|

  @buckets 60

  @doc """
  The newest 100 issues by last occurrence in the window, matching a literal
  title search, each with its occurrence series.
  """
  def issues(opts, request) do
    search =
      if opts.query == "*", do: "", else: " AND strpos(lower(title), lower(#{literal(opts.query)})) > 0"

    window = "#{bounds(opts.finish - opts.seconds, opts.finish)}#{search}#{environment(opts.params)}"

    query =
      "SELECT #{@issue_columns} FROM errors WHERE #{window} " <>
        "GROUP BY service, fingerprint ORDER BY last_seen DESC, service ASC, fingerprint ASC LIMIT 100"

    with {:ok, rows} <- sql(request, query),
         true <- Enum.all?(rows, &valid_issue?/1),
         {:ok, series} <- issue_series(rows, window, opts, request) do
      rows = Enum.map(rows, &(&1 |> issue() |> Map.put("occurrence_series", Map.fetch!(series, issue_key(&1)))))
      {:ok, %{rows: rows, series: [], warnings: []}}
    else
      false -> {:error, :malformed_response}
      error -> error
    end
  end

  # Issues group events, so an environment filter selects the events counted
  # rather than filtering grouped rows afterwards.
  defp environment(%{"environment" => value} = params) when value != "" do
    actual = "lower(coalesce(environment, ''))"

    case Map.get(params, "environment_op", "eq") do
      "eq" -> " AND environment = #{literal(value)}"
      "contains" -> " AND strpos(#{actual}, lower(#{literal(value)})) > 0"
      "not_contains" -> " AND strpos(#{actual}, lower(#{literal(value)})) = 0"
    end
  end

  defp environment(_params), do: ""

  defp issue_series([], _window, _opts, _request), do: {:ok, %{}}

  # One grouped read for every listed issue. Fingerprints narrow the scan;
  # unlisted services sharing a fingerprint are dropped when bucketing.
  defp issue_series(rows, window, opts, request) do
    fingerprints = rows |> Enum.map(& &1["fingerprint"]) |> Enum.uniq() |> Enum.map_join(", ", &literal/1)

    query =
      "SELECT service, fingerprint, #{bucket(opts)} AS bucket, count(DISTINCT event_id) AS events FROM errors " <>
        "WHERE #{window} AND fingerprint IN (#{fingerprints}) GROUP BY service, fingerprint, bucket"

    with {:ok, buckets} <- sql(request, query),
         true <- Enum.all?(buckets, &valid_bucket?/1) do
      counts = Enum.group_by(buckets, &issue_key/1)
      {:ok, Map.new(rows, &{issue_key(&1), series(Map.get(counts, issue_key(&1), []), opts)})}
    else
      false -> {:error, :malformed_response}
      error -> error
    end
  end

  @doc """
  One issue in the window: its summary, its occurrence series, the latest event
  with its scrubbed payload, and one page of events, newest first, with
  pagination metadata.
  """
  def issue(service, fingerprint, opts, request) do
    scope = scope(service, fingerprint, opts)

    with {:ok, summaries} <-
           sql(request, "SELECT #{@issue_columns} FROM errors WHERE #{scope} GROUP BY service, fingerprint"),
         {:ok, [summary]} <- one(summaries),
         {:ok, buckets} <-
           sql(
             request,
             "SELECT #{bucket(opts)} AS bucket, count(DISTINCT event_id) AS events FROM errors WHERE #{scope} GROUP BY bucket"
           ),
         {:ok, events} <-
           sql(
             request,
             "SELECT DISTINCT #{@event_columns} FROM errors WHERE #{scope} ORDER BY timestamp DESC, event_id ASC " <>
               "LIMIT #{opts.page_size} OFFSET #{(opts.page - 1) * opts.page_size}"
           ),
         {:ok, latest} <-
           sql(
             request,
             "SELECT #{@event_columns}, event FROM errors WHERE #{scope} ORDER BY timestamp DESC, event_id ASC LIMIT 1"
           ),
         true <- valid_issue?(summary) and Enum.all?(events ++ latest, &valid_event?/1),
         true <- Enum.all?(buckets, &valid_bucket?/1) do
      {:ok,
       %{
         issue: issue(summary),
         occurrence_series: series(buckets, opts),
         latest_event: detail(hd(latest)),
         events: Enum.map(events, &event/1),
         meta: meta(summary["events"], opts),
         warnings: []
       }}
    else
      false -> {:error, :malformed_response}
      error -> error
    end
  end

  @doc "One event of an issue in the window, with its scrubbed payload."
  def event(service, fingerprint, event_id, opts, request) do
    scope = "#{scope(service, fingerprint, opts)} AND event_id = #{literal(event_id)}"

    with {:ok, rows} <-
           sql(request, "SELECT #{@event_columns}, event FROM errors WHERE #{scope} ORDER BY timestamp DESC LIMIT 1"),
         {:ok, [row]} <- one(rows),
         true <- valid_event?(row) do
      {:ok, %{event: detail(row), warnings: []}}
    else
      false -> {:error, :malformed_response}
      error -> error
    end
  end

  defp scope(service, fingerprint, opts),
    do:
      "#{bounds(opts.finish - opts.seconds, opts.finish)} AND service = #{literal(service)} " <>
        "AND fingerprint = #{literal(fingerprint)}#{environment(opts.params)}"

  defp bucket(opts) do
    start = opts.finish - opts.seconds
    "(arrow_cast(timestamp, 'Int64') - #{start * 1_000_000_000}) / #{div(opts.seconds, @buckets) * 1_000_000_000}"
  end

  # The window's end is inclusive, so its boundary falls into the last bucket.
  defp series(buckets, opts) do
    start = opts.finish - opts.seconds
    width = div(opts.seconds, @buckets)

    counts =
      Enum.reduce(buckets, %{}, fn row, counts ->
        Map.update(counts, min(max(row["bucket"], 0), @buckets - 1), row["events"], &(&1 + row["events"]))
      end)

    Enum.map(0..(@buckets - 1), &[start + &1 * width, Map.get(counts, &1, 0)])
  end

  defp meta(count, opts) do
    total_pages = ceil(count / opts.page_size)

    %{
      "page" => opts.page,
      "page_size" => opts.page_size,
      "total_count" => count,
      "total_pages" => total_pages,
      "end_at" => opts.end_at,
      "has_next_page" => opts.page < total_pages,
      "has_previous_page" => opts.page > 1
    }
  end

  defp issue_key(row), do: {row["service"], row["fingerprint"]}

  defp one([]), do: {:error, :not_found}
  defp one([_] = rows), do: {:ok, rows}
  defp one(_), do: {:error, :malformed_response}

  defp issue(row) do
    row
    |> Map.update!("first_seen", &Integer.to_string/1)
    |> Map.update!("last_seen", &Integer.to_string/1)
  end

  defp event(row) do
    row |> Map.delete("event") |> Map.update!("timestamp", &Integer.to_string/1)
  end

  defp detail(row), do: row |> event() |> Map.merge(payload(row["event"]))

  # The pipeline's projection; anything else in the column is ignored.
  defp payload(event) when is_map(event) do
    Map.new(~w(exception breadcrumbs tags extra contexts request message), &{&1, Map.get(event, &1)})
  end

  defp payload(_event), do: %{}

  defp valid_issue?(row) do
    Enum.all?(~w(service fingerprint), &is_binary(row[&1])) and
      Enum.all?(~w(title culprit level platform environment latest_event_id), &(is_binary(row[&1]) or is_nil(row[&1]))) and
      Enum.all?(~w(events accounts environments first_seen last_seen), &(is_integer(row[&1]) and row[&1] >= 0))
  end

  defp valid_bucket?(row), do: is_integer(row["bucket"]) and is_integer(row["events"]) and row["events"] >= 0

  defp valid_event?(row) do
    is_integer(row["timestamp"]) and row["timestamp"] >= 0 and
      Enum.all?(
        ~w(event_id title level environment release server_name trace_id account_handle sdk),
        &(is_binary(row[&1]) or is_nil(row[&1]))
      )
  end
end
