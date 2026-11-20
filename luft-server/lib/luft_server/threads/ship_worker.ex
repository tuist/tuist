defmodule LuftServer.Threads.ShipWorker do
  @moduledoc "Single-dispatch Ship job, sharing the thread's local lease with inference hosts."
  use Oban.Worker,
    queue: :threads,
    max_attempts: 5,
    unique: [
      period: :infinity,
      keys: [:run_id],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias LuftServer.Agents.Lease
  alias LuftServer.Repo
  alias LuftServer.Threads
  alias LuftServer.Threads.Run

  @impl Oban.Worker
  def perform(job), do: perform(job, [])

  def perform(%Oban.Job{args: %{"run_id" => id}}, opts) do
    case Repo.get(Run, id) do
      %Run{kind: "ship", status: status} = run when status in ["queued", "running"] ->
        host = "ship:#{id}:#{Ecto.UUID.generate()}"

        case acquire(run, host) do
          {epoch, seq} ->
            try do
              case Threads.claim_ship(id, epoch) do
                {:ok, {claimed, _, _}} -> execute(claimed, host, opts)
                {:ok, _} -> :ok
                {:error, reason} when reason in [:tuist_unavailable, :stale_run] -> {:snooze, 5}
                {:error, _} -> {:snooze, 30}
              end
            after
              Lease.release(run.thread_id, epoch, wanted: false, seen: seq)
            end

          nil ->
            {:snooze, 5}
        end

      _ ->
        :ok
    end
  end

  # Never claim unrelated sessions. An active inference host must first release
  # this same thread lease; all side effects continue to use its shared epoch.
  defp acquire(run, host) do
    case Repo.query!(
           """
           UPDATE agent_sessions SET epoch=epoch+1, host=$2,
             lease_expires_at=CURRENT_TIMESTAMP + interval '20 seconds'
           WHERE id=$1 AND deleted_at IS NULL AND
             (lease_expires_at IS NULL OR lease_expires_at < CURRENT_TIMESTAMP)
           RETURNING epoch, want_seq
           """,
           [run.thread_id, host],
           log: false
         ).rows do
      [[epoch, seq]] -> {epoch, seq}
      [] -> nil
    end
  end

  defp execute(run, host, opts) do
    task = Task.async(fn -> Threads.execute_ship(run, opts) end)
    await(task, run, host)
  end

  defp await(task, run, host) do
    case Task.yield(task, 5_000) do
      {:ok, {:ok, _}} ->
        :ok

      {:ok, _} ->
        Threads.ship_interrupted(run)
        :ok

      nil ->
        if Map.has_key?(
             Lease.renew(host, [{run.thread_id, run.attempt}]),
             {run.thread_id, run.attempt}
           ) do
          await(task, run, host)
        else
          Task.shutdown(task, :brutal_kill)
          Threads.ship_interrupted(run)
          :ok
        end
    end
  end
end
