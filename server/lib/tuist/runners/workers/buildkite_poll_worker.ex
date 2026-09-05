defmodule Tuist.Runners.Workers.BuildkitePollWorker do
  @moduledoc """
  Drives the Buildkite lane's pull loop.

  GitHub tells us a job is queued within a second of it being queued.
  Buildkite tells us nothing, so this worker asks. Oban's cron is
  minute-granular and a minute of dispatch latency on every job would be
  worse than the GitHub lane by an order of magnitude, so each run holds
  its slot for close to a minute and polls inside it. The cron entry is
  then a supervisor rather than a scheduler: if a run dies, the next
  minute starts a fresh one.

  Uniqueness is per installation and covers the whole run window, so two
  server pods cannot poll the same stack concurrently and burn its 10 rps
  listing budget twice over.

  A run stops early when the installation's credentials are rejected.
  Retrying a revoked token for the rest of the minute would spend the
  budget on calls that cannot succeed, and the error is recorded on the
  installation for the settings page to show.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [period: 120, keys: [:installation_id], states: [:available, :scheduled, :executing]]

  alias Tuist.Runners.Buildkite

  require Logger

  @run_window_ms to_timeout(second: 55)
  @poll_interval_ms to_timeout(second: 5)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"installation_id" => installation_id}}) do
    case Enum.find(Buildkite.list_pollable_installations(), &(&1.id == installation_id)) do
      nil -> :ok
      installation -> run_window(installation, deadline())
    end
  end

  def perform(_job) do
    Enum.each(Buildkite.list_pollable_installations(), fn installation ->
      %{installation_id: installation.id}
      |> __MODULE__.new()
      |> Oban.insert()
    end)

    :ok
  end

  defp deadline, do: System.monotonic_time(:millisecond) + @run_window_ms

  defp run_window(installation, deadline) do
    result = Buildkite.poll(installation)
    Buildkite.record_poll_result(installation, normalize(result))

    cond do
      match?({:error, _reason}, result) ->
        Logger.warning("runners: buildkite poll failed",
          installation_id: installation.id,
          reason: inspect(elem(result, 1))
        )

        :ok

      System.monotonic_time(:millisecond) + @poll_interval_ms >= deadline ->
        :ok

      true ->
        Process.sleep(@poll_interval_ms)
        run_window(installation, deadline)
    end
  end

  defp normalize({:ok, _count}), do: :ok
  defp normalize({:error, _reason} = error), do: error
end
