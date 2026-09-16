defmodule Tuist.Kura.Workers.AwaitActivationWorker do
  @moduledoc """
  Activates a Kura instance that is coming up within about a second of its
  endpoint answering, rather than on the next minute's reconciler tick.

  Each run checks `Tuist.Kura.Reconciler.activate_when_ready/1` about once a
  second, up to `@checks_per_run` times, then snoozes without a delay. Snoozing
  after every check would space them by Oban's stager and fetch, measured at
  2.5 to 3 seconds apart, so each run keeps its own clock and only pays that
  gap once per run. The run stays short of Oban's 15-second shutdown grace
  period, so a deploy does not orphan it. It gives up once the attempt has run for
  `Tuist.Kura.provisioning_stall_seconds/0`, where the tick reports the stall
  and keeps retrying on its own cadence.
  """
  use Oban.Worker,
    queue: :kura_provisioning,
    max_attempts: 1,
    unique: [keys: [:server_id], period: :infinity, states: :incomplete]

  alias Tuist.Environment
  alias Tuist.Kura
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Reconciler
  alias Tuist.Kura.Server

  @checks_per_run 13
  @check_interval_ms Application.compile_env(:tuist, [__MODULE__, :check_interval_ms], 1_000)

  def enqueue(%Server{id: server_id}) do
    %{server_id: server_id}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"server_id" => server_id}}) do
    if Environment.kura_control_plane?(), do: check(server_id, @checks_per_run), else: :ok
  end

  defp check(server_id, remaining) do
    with {:waiting, %Deployment{inserted_at: started_at}} <- Reconciler.activate_when_ready(server_id),
         true <- DateTime.diff(DateTime.utc_now(), started_at) < Kura.provisioning_stall_seconds() do
      if remaining > 1 do
        Process.sleep(@check_interval_ms)
        check(server_id, remaining - 1)
      else
        {:snooze, 0}
      end
    else
      _ -> :ok
    end
  end
end
