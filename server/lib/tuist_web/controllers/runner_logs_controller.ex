defmodule TuistWeb.RunnerLogsController do
  @moduledoc """
  Ingest endpoint the in-VM/in-Pod log shipper streams a runner job's
  stdout to, line by line.

  Authentication: the per-job `log_token` minted by the dispatch
  endpoint (see `TuistWeb.RunnerLogToken`) — verified locally, so this
  high-frequency path never round-trips the Kubernetes `TokenReview`
  API. The token, not the request body, decides which job + account a
  batch is attributed to.

  Each batch is appended to ClickHouse (`Tuist.Runners.JobLogs`) and
  broadcast on the job's Pub/Sub topic so an open detail page tails it
  live. The first batch (the one carrying line 1) flips the job to
  `log_state = "streaming"`; the shipper's closing batch (`done: true`)
  finalizes it to `complete`/`partial` with the captured line count.
  """
  use TuistWeb, :controller

  alias Tuist.Runners.JobLogs
  alias Tuist.Runners.Jobs
  alias TuistWeb.RunnerLogToken

  require Logger

  @doc """
  `POST /api/internal/runners/logs`

  Request body:

      {
        "lines": [{"n": 1, "ts": "2026-05-28T12:00:00Z", "message": "..."}],
        "done": false,
        "partial": false
      }

  Responses:

    * 202 — batch accepted.
    * 400 — malformed `lines` payload.
    * 401 — missing or invalid `log_token`.
  """
  def ingest(conn, params) do
    with {:ok, token} <- bearer_token(conn),
         {:ok, %{workflow_job_id: workflow_job_id, account_id: account_id}} <- RunnerLogToken.verify(token),
         {:ok, lines} <- parse_lines(params, workflow_job_id, account_id) do
      :ok = JobLogs.append(lines)
      broadcast(workflow_job_id, lines)
      maybe_mark_streaming(workflow_job_id, lines)
      maybe_finalize(workflow_job_id, params, lines)

      send_resp(conn, :accepted, "")
    else
      {:error, :missing_bearer} ->
        conn |> put_status(:unauthorized) |> json(%{error: "missing log token"})

      {:error, :invalid_token} ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid log token"})

      {:error, :invalid_lines} ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid lines payload"})
    end
  end

  defp parse_lines(params, workflow_job_id, account_id) do
    case Map.get(params, "lines", []) do
      lines when is_list(lines) ->
        {:ok, Enum.map(lines, &line_row(&1, workflow_job_id, account_id))}

      _ ->
        {:error, :invalid_lines}
    end
  end

  defp line_row(line, workflow_job_id, account_id) when is_map(line) do
    %{
      workflow_job_id: workflow_job_id,
      account_id: account_id,
      line_number: parse_line_number(Map.get(line, "n")),
      ts: parse_ts(Map.get(line, "ts")),
      message: to_message(Map.get(line, "message"))
    }
  end

  defp line_row(_, workflow_job_id, account_id), do: line_row(%{}, workflow_job_id, account_id)

  defp parse_line_number(n) when is_integer(n) and n >= 0, do: n
  defp parse_line_number(_), do: 0

  # Runner output prefixes every line with an ISO-8601 stamp; fall
  # back to ingest time when a line arrives without (or with an
  # unparseable) timestamp so per-step slicing still has an anchor.
  # The `DateTime64(6)` column dumps as `:utc_datetime_usec`, which
  # requires the value to carry 6-digit microsecond precision. A
  # second- or millisecond-precision stamp keeps its microsecond value
  # but advertises fewer digits, so force the precision to 6.
  defp parse_ts(ts) when is_binary(ts) and ts != "" do
    case DateTime.from_iso8601(ts) do
      {:ok, datetime, _offset} -> with_usec_precision(datetime)
      _ -> DateTime.utc_now()
    end
  end

  defp parse_ts(_), do: DateTime.utc_now()

  defp with_usec_precision(%DateTime{microsecond: {value, _precision}} = datetime) do
    %{datetime | microsecond: {value, 6}}
  end

  defp to_message(message) when is_binary(message), do: message
  defp to_message(nil), do: ""
  defp to_message(other), do: to_string(other)

  defp broadcast(_workflow_job_id, []), do: :ok

  defp broadcast(workflow_job_id, lines) do
    Tuist.PubSub.broadcast(%{lines: lines}, JobLogs.topic(workflow_job_id), :runner_job_log_lines)
    :ok
  end

  # The batch carrying line 1 is the first one — flip the job to
  # `streaming` so the detail page knows to live-tail.
  defp maybe_mark_streaming(workflow_job_id, lines) do
    if Enum.any?(lines, &(&1.line_number == 1)) do
      Jobs.set_log_state(workflow_job_id, "streaming")
    end

    :ok
  end

  defp maybe_finalize(workflow_job_id, %{"done" => true} = params, lines) do
    state = if Map.get(params, "partial", false) == true, do: "partial", else: "complete"
    Jobs.set_log_state(workflow_job_id, state, line_count: final_line_count(workflow_job_id, lines))
  end

  defp maybe_finalize(_workflow_job_id, _params, _lines), do: :ok

  # Line numbers are monotonic, so the highest in the closing batch is
  # the total. An empty closing batch (the runner died with nothing
  # left to flush) falls back to counting what we stored.
  defp final_line_count(workflow_job_id, []), do: JobLogs.count_for_job(workflow_job_id)
  defp final_line_count(_workflow_job_id, lines), do: lines |> Enum.map(& &1.line_number) |> Enum.max()

  defp bearer_token(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> {:ok, token}
      ["bearer " <> token] when token != "" -> {:ok, token}
      _ -> {:error, :missing_bearer}
    end
  end
end
