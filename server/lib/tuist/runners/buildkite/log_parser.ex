defmodule Tuist.Runners.Buildkite.LogParser do
  @moduledoc """
  Turns a `buildkite-agent` job log line into the shape
  `runner_job_logs` stores.

  The agent timestamps output inline rather than by prefix: it emits an
  OSC escape, `ESC _bk;t=<milliseconds since epoch> BEL`, ahead of the
  text it applies to, which is how Buildkite's own web log renders
  per-line times. GitHub's Actions log prefixes an ISO-8601 timestamp and
  a space instead, which is what `FetchLogsWorker.parse_lines/3` reads.
  Both end up as the same `(ts, message)` pair, so the stored log and
  everything that reads it stay provider-agnostic.

  A line with no marker carries the previous line's timestamp forward, so
  per-step slicing stays monotonic — the same rule the GitHub parser
  applies for the same reason.
  """

  @timestamp_marker ~r/\x1b_bk;t=(\d+)\x07/
  # The agent emits other `bk` OSC payloads besides timestamps (and could
  # emit more later). Stripping the whole family, rather than only the
  # timestamps read above, keeps escape bytes we do not interpret out of
  # the stored message instead of rendering them at the customer.
  @any_marker ~r/\x1b_bk;[^\x07]*\x07/

  @doc """
  Parses `lines` into log rows, numbered from `first_line_number`.

  `fallback_ts` timestamps the leading lines of a chunk that opens
  before the agent's first marker.
  """
  def parse(lines, first_line_number, fallback_ts) when is_list(lines) do
    {rows, _last_ts} =
      lines
      |> Enum.with_index(first_line_number)
      |> Enum.map_reduce(fallback_ts, fn {line, line_number}, last_ts ->
        {ts, message} = parse_line(line, last_ts)
        {%{line_number: line_number, ts: ts, message: message}, ts}
      end)

    rows
  end

  @doc """
  The timestamp and text of one line.
  """
  def parse_line(line, last_ts) when is_binary(line) do
    case Regex.run(@timestamp_marker, line, capture: :all_but_first) do
      [milliseconds] -> {timestamp(milliseconds, last_ts), strip(line)}
      nil -> {last_ts, strip(line)}
    end
  end

  defp timestamp(milliseconds, last_ts) do
    case Integer.parse(milliseconds) do
      {value, ""} -> value |> DateTime.from_unix!(:millisecond) |> with_usec_precision()
      _ -> last_ts
    end
  end

  # `DateTime64(6)` on the ClickHouse column wants microsecond
  # precision; a millisecond epoch advertises 3.
  defp with_usec_precision(%DateTime{microsecond: {value, _precision}} = datetime) do
    %{datetime | microsecond: {value, 6}}
  end

  defp strip(line) do
    line
    |> String.replace(@any_marker, "")
    |> String.trim_trailing("\r")
  end
end
