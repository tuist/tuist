defmodule Tuist.Kura.Workers.AwaitActivationWorker do
  @moduledoc """
  Activates a Kura instance that is coming up within about a second of its
  endpoint answering, rather than on the next minute's reconciler tick.

  Checks `Tuist.Kura.Reconciler.activate_when_ready/1` and snoozes for a
  second while the deployment is still open. It gives up once the attempt has
  run for `Tuist.Kura.provisioning_stall_seconds/0`, where the tick reports the
  stall and keeps retrying on its own cadence.
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

  @poll_seconds 1

  def enqueue(%Server{id: server_id}) do
    %{server_id: server_id}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"server_id" => server_id}}) do
    with true <- Environment.kura_control_plane?(),
         {:waiting, %Deployment{inserted_at: started_at}} <- Reconciler.activate_when_ready(server_id),
         true <- DateTime.diff(DateTime.utc_now(), started_at) < Kura.provisioning_stall_seconds() do
      {:snooze, @poll_seconds}
    else
      _ -> :ok
    end
  end
end
