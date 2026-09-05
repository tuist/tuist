defmodule Tuist.Sandboxes.Workers.PauseSandboxWorker do
  @moduledoc """
  Pauses a sandbox once its worker has been gone for the grace period.

  Scheduled by `Tuist.Sandboxes.end_residency/1` with the residency
  epoch current at that moment. A new residency bumps the epoch, so a
  job enqueued for an earlier exit finds a mismatch and does nothing;
  the newer exit schedules its own job. Uniqueness is keyed on the
  sandbox so at most one pause is pending per sandbox, with the newest
  exit replacing the args and schedule of a pending one.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:sandbox_id], states: [:available, :scheduled], period: :infinity]

  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Sandbox

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"sandbox_id" => sandbox_id, "residency_epoch" => epoch}}) do
    case Sandboxes.get_sandbox_by_id(sandbox_id) do
      %Sandbox{state: :running, residency_work_id: nil, residency_epoch: ^epoch} = sandbox ->
        pause(sandbox)

      _ ->
        :ok
    end
  end

  defp pause(sandbox) do
    case Sandboxes.pause(sandbox) do
      {:ok, _sandbox} ->
        :ok

      {:error, reason} ->
        Logger.warning("sandboxes: scheduled pause failed",
          sandbox_id: sandbox.id,
          node: sandbox.node_name,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end
end
