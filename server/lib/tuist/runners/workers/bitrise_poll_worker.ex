defmodule Tuist.Runners.Workers.BitrisePollWorker do
  @moduledoc """
  Drives the Bitrise lane's pull loop, with the same shape as
  `BuildkitePollWorker`: the minute cron fans out one job per connection,
  and each job polls inside a window of close to a minute so a build waits
  seconds, not a minute, to be queued.

  A run stops early on a rejected token, and records the error on the
  connection for the settings page.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [period: 120, keys: [:connection_id], states: [:available, :scheduled, :executing]]

  alias Tuist.Runners.Bitrise

  require Logger

  @run_window_ms to_timeout(second: 55)
  @poll_interval_ms to_timeout(second: 5)
  @halting_errors [:unauthorized, :forbidden, :not_found, :no_account, :no_pools]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"connection_id" => connection_id}}) do
    case Enum.find(Bitrise.list_pollable_connections(), &(&1.id == connection_id)) do
      nil -> :ok
      connection -> run_window(connection, deadline())
    end
  end

  def perform(_job) do
    Enum.each(Bitrise.list_pollable_connections(), fn connection ->
      %{connection_id: connection.id}
      |> __MODULE__.new()
      |> Oban.insert()
    end)

    :ok
  end

  defp deadline, do: System.monotonic_time(:millisecond) + @run_window_ms

  defp run_window(connection, deadline) do
    result = Bitrise.poll(connection)
    Bitrise.record_poll_result(connection, normalize(result))

    cond do
      match?({:error, reason} when reason in @halting_errors, result) ->
        Logger.warning("runners: bitrise poll failed",
          connection_id: connection.id,
          reason: inspect(elem(result, 1))
        )

        :ok

      System.monotonic_time(:millisecond) + @poll_interval_ms >= deadline ->
        :ok

      true ->
        Process.sleep(@poll_interval_ms)
        run_window(connection, deadline)
    end
  end

  defp normalize({:ok, _count}), do: :ok
  defp normalize({:error, _reason} = error), do: error
end
