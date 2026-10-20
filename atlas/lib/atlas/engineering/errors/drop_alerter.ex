defmodule Atlas.Engineering.Errors.DropAlerter do
  @moduledoc """
  Out-of-band visibility for events dropped by the ingest pipeline.

  The ingest path is fire-and-forget past the HTTP response, so a buffer
  flush failure or a per-event error would otherwise disappear silently
  and we can't route the notification back through the ClickHouse
  pipeline that just failed. This module accepts async reports of drops,
  coalesces them into per-reason buckets over a configurable window
  (default 60 s), and, on each tick:

    1. Emits a `[:atlas, :engineering, :errors, :ingest, :dropped]`
       telemetry event so Prometheus / Grafana consumers can alert
       independently.
    2. Posts a Slack message to
       `Application.get_env(:atlas, :default_alert_slack_channel)`, if
       one is configured and the company Slack app is installed.
    3. Falls back to `Logger.warning/2` on the `:atlas_alerts` domain
       so operators on any log aggregator still see the failure.

  Report call sites are one-liners:

      DropAlerter.report_flush_failure(name, byte_size, exception)
      DropAlerter.report_ingest_failure(reason, sample_meta)

  Both are `GenServer.cast` — never block the ingest hot path.
  """

  use GenServer

  alias Atlas.Slack.API

  require Logger

  @app_key :company
  @flush_interval_ms :timer.seconds(60)
  @sample_limit 500

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Reports a batch of events dropped because the ClickHouse buffer
  couldn't flush. `name` is the buffer module, `byte_size` is the
  RowBinary payload size that was dropped, `exception` is the raised
  error.
  """
  def report_flush_failure(name, byte_size, exception) do
    GenServer.cast(
      __MODULE__,
      {:report, :flush_failure, %{name: inspect(name), byte_size: byte_size, sample: format_exception(exception)}}
    )
  end

  @doc """
  Reports a single event dropped during envelope ingestion because
  `record_event/2` returned an error other than `:not_configured` (an
  expected outcome when ClickHouse is disabled).
  """
  def report_ingest_failure(reason, sample_meta \\ %{}) do
    GenServer.cast(
      __MODULE__,
      {:report, :ingest_failure, Map.merge(%{sample: format_reason(reason)}, sample_meta)}
    )
  end

  @doc """
  Forces an immediate flush of pending buckets. Only used in tests.
  """
  def flush(server \\ __MODULE__) do
    GenServer.call(server, :flush, :infinity)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    interval = Keyword.get(opts, :flush_interval_ms, @flush_interval_ms)
    timer = Process.send_after(self(), :tick, interval)
    {:ok, %{buckets: %{}, timer: timer, interval: interval}}
  end

  @impl true
  def handle_cast({:report, reason, meta}, state) do
    now = DateTime.utc_now()

    buckets =
      Map.update(state.buckets, reason, new_bucket(now, meta), fn bucket ->
        %{
          bucket
          | count: bucket.count + 1,
            last_at: now,
            # Keep the FIRST sample so operators see the initial failure
            # rather than a rotating tail. Truncate to protect memory
            # under a sustained storm.
            sample: truncate_sample(bucket.sample)
        }
      end)

    {:noreply, %{state | buckets: buckets}}
  end

  @impl true
  def handle_info(:tick, state) do
    do_flush(state.buckets)
    timer = Process.send_after(self(), :tick, state.interval)
    {:noreply, %{state | buckets: %{}, timer: timer}}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    Process.cancel_timer(state.timer)
    do_flush(state.buckets)
    timer = Process.send_after(self(), :tick, state.interval)
    {:reply, :ok, %{state | buckets: %{}, timer: timer}}
  end

  @impl true
  def terminate(_reason, %{buckets: buckets}) do
    do_flush(buckets)
  end

  defp new_bucket(now, meta) do
    %{
      count: 1,
      first_at: now,
      last_at: now,
      sample: Map.get(meta, :sample, "") |> truncate_sample()
    }
    |> Map.merge(Map.delete(meta, :sample))
  end

  defp truncate_sample(nil), do: ""

  defp truncate_sample(bin) when is_binary(bin) do
    if byte_size(bin) > @sample_limit,
      do: binary_part(bin, 0, @sample_limit) <> "...",
      else: bin
  end

  defp truncate_sample(other), do: truncate_sample(inspect(other))

  defp do_flush(buckets) when map_size(buckets) == 0, do: :ok

  defp do_flush(buckets) do
    Enum.each(buckets, fn {reason, bucket} ->
      :telemetry.execute(
        [:atlas, :engineering, :errors, :ingest, :dropped],
        %{count: bucket.count},
        %{reason: reason, first_at: bucket.first_at, last_at: bucket.last_at}
      )

      case post_to_slack(reason, bucket) do
        {:ok, text} ->
          Logger.warning(
            "atlas_alerts: paged Slack — #{text}",
            domain: [:atlas_alerts]
          )

        {:error, {why, text}} ->
          Logger.warning(
            "atlas_alerts: #{text} (Slack post skipped: #{inspect(why)}) sample=#{bucket.sample}",
            domain: [:atlas_alerts]
          )
      end
    end)
  end

  # Slack payload shaped for maximum operator alarm: red-bordered
  # attachment (rendered as blocks here, since Atlas.Slack.API takes
  # blocks + fallback text), header block, @channel ping, fields grid,
  # and a danger-styled button that links straight to the Atlas
  # engineering errors dashboard. The plain fallback text is what
  # mobile push notifications actually show, so it repeats the count +
  # buffer so an operator can triage without opening Slack.
  defp slack_payload(:flush_failure, bucket) do
    fallback =
      "🚨 ATLAS INGEST BROKEN — #{bucket.count} failed flush attempt(s), " <>
        "buffer #{Map.get(bucket, :name, "?")} dropping events on the floor"

    blocks = [
      %{
        "type" => "header",
        "text" => %{
          "type" => "plain_text",
          "text" => "🚨🚨 ATLAS ERROR INGEST BROKEN 🚨🚨",
          "emoji" => true
        }
      },
      %{
        "type" => "section",
        "text" => %{
          "type" => "mrkdwn",
          "text" =>
            "<!channel> — errors from production services are being *dropped on the floor*. " <>
              "The ClickHouse buffer can't flush. *Investigate now* — every minute this " <>
              "runs, real customer errors are lost."
        }
      },
      %{
        "type" => "section",
        "fields" => [
          %{"type" => "mrkdwn", "text" => "*What broke*\nClickHouse buffer flush"},
          %{"type" => "mrkdwn", "text" => "*Failed flushes*\n#{bucket.count}"},
          %{"type" => "mrkdwn", "text" => "*Buffer*\n`#{Map.get(bucket, :name, "?")}`"},
          %{
            "type" => "mrkdwn",
            "text" => "*Bytes dropped (last)*\n#{Map.get(bucket, :byte_size, 0)}"
          },
          %{
            "type" => "mrkdwn",
            "text" => "*First failure*\n#{DateTime.to_iso8601(bucket.first_at)}"
          },
          %{
            "type" => "mrkdwn",
            "text" => "*Last failure*\n#{DateTime.to_iso8601(bucket.last_at)}"
          }
        ]
      },
      %{
        "type" => "section",
        "text" => %{
          "type" => "mrkdwn",
          "text" => "*Sample exception*\n```#{bucket.sample}```"
        }
      }
      | dashboard_button_blocks()
    ]

    {blocks, fallback}
  end

  defp slack_payload(:ingest_failure, bucket) do
    fallback =
      "🚨 ATLAS INGEST BROKEN — #{bucket.count} event(s) dropped by the ingest pipeline"

    blocks = [
      %{
        "type" => "header",
        "text" => %{
          "type" => "plain_text",
          "text" => "🚨 ATLAS INGEST DROPPING EVENTS 🚨",
          "emoji" => true
        }
      },
      %{
        "type" => "section",
        "text" => %{
          "type" => "mrkdwn",
          "text" =>
            "<!channel> — `Atlas.Engineering.Errors.ingest_envelope/2` is rejecting events. " <>
              "Likely a Postgres or ClickHouse fault upstream of the buffer. " <>
              "*Investigate now.*"
        }
      },
      %{
        "type" => "section",
        "fields" => [
          %{"type" => "mrkdwn", "text" => "*Dropped events*\n#{bucket.count}"},
          %{
            "type" => "mrkdwn",
            "text" => "*First failure*\n#{DateTime.to_iso8601(bucket.first_at)}"
          },
          %{
            "type" => "mrkdwn",
            "text" => "*Last failure*\n#{DateTime.to_iso8601(bucket.last_at)}"
          }
        ]
      },
      %{
        "type" => "section",
        "text" => %{
          "type" => "mrkdwn",
          "text" => "*Sample reason*\n```#{bucket.sample}```"
        }
      }
      | dashboard_button_blocks()
    ]

    {blocks, fallback}
  end

  defp dashboard_button_blocks do
    case dashboard_url() do
      nil ->
        []

      url ->
        [
          %{
            "type" => "actions",
            "elements" => [
              %{
                "type" => "button",
                "text" => %{"type" => "plain_text", "text" => "Open Atlas errors", "emoji" => true},
                "url" => url,
                "style" => "danger"
              }
            ]
          }
        ]
    end
  end

  defp dashboard_url do
    if Code.ensure_loaded?(AtlasWeb.Endpoint) and
         function_exported?(AtlasWeb.Endpoint, :url, 0) do
      AtlasWeb.Endpoint.url() <> "/engineering/errors"
    end
  rescue
    _ -> nil
  end

  defp post_to_slack(reason, bucket) do
    {blocks, fallback} = slack_payload(reason, bucket)

    case fetch_channel_id() do
      {:ok, channel_id} ->
        case API.post_message(@app_key, channel_id, fallback, blocks) do
          {:ok, _} -> {:ok, fallback}
          {:error, why} -> {:error, {why, fallback}}
        end

      {:error, why} ->
        {:error, {why, fallback}}
    end
  rescue
    error ->
      {_blocks, fallback} = slack_payload(reason, bucket)
      {:error, {{:exception, Exception.message(error)}, fallback}}
  end

  defp fetch_channel_id do
    case Application.get_env(:atlas, :default_alert_slack_channel) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :no_channel_configured}
    end
  end

  defp format_exception(exception) do
    if is_exception(exception),
      do: Exception.message(exception),
      else: inspect(exception)
  end

  defp format_reason(reason), do: inspect(reason, limit: 5, printable_limit: 200)
end
