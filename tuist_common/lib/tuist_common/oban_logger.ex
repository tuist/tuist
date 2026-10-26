defmodule TuistCommon.ObanLogger do
  @moduledoc """
  Logs Oban lifecycle events without copying job arguments into service logs.
  """

  require Logger

  def attach do
    :telemetry.attach_many(
      "tuist-oban-logger",
      [[:oban, :job, :start], [:oban, :job, :stop], [:oban, :job, :exception]],
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def handle_event([:oban, :job, event], measurements, %{job: job} = metadata, _config) do
    level =
      case event do
        :start -> :debug
        :exception -> :error
        :stop -> :info
      end

    Logger.log(level, fn ->
      identity =
        "Oban job #{event} worker=#{job.worker} job_id=#{job.id} queue=#{job.queue} " <>
          "attempt=#{job.attempt} max_attempts=#{job.max_attempts}"

      details =
        measurements
        |> Map.take([:duration, :queue_time])
        |> Enum.sort()
        |> Enum.map_join("", fn {key, value} ->
          milliseconds = System.convert_time_unit(value, :native, :microsecond) / 1_000
          " #{key}_ms=#{:erlang.float_to_binary(milliseconds, [{:decimals, 3}, :compact])}"
        end)

      state = if metadata[:state], do: " state=#{metadata.state}", else: ""

      exception =
        if event == :exception do
          banner =
            metadata.kind
            |> Exception.format_banner(metadata.reason, metadata.stacktrace)
            |> diagnostic_part()

          stacktrace =
            metadata.stacktrace
            |> Exception.format_stacktrace()
            |> diagnostic_part()

          diagnostic = String.slice(banner <> " | " <> stacktrace, 0, 4_096)

          " exception=#{diagnostic}"
        else
          ""
        end

      identity <> details <> state <> exception
    end)
  end

  defp diagnostic_part(text) do
    text
    |> String.slice(0, 2_048)
    |> String.replace(~r/[\r\n]+/, " | ")
    |> String.slice(0, 2_048)
  end
end
