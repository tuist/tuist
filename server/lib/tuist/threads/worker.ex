defmodule Tuist.Threads.Worker do
  @moduledoc "Runs an approved Ship as a one-off job. Inference runs are hosted by `Tuist.Threads.Host`; an inference job an earlier release enqueued hands its run to the thread's session."
  use Oban.Worker,
    queue: :threads,
    max_attempts: 3,
    unique: [period: :infinity, keys: [:run_id, :attempt], states: [:available, :scheduled, :executing, :retryable]]

  alias Tuist.Agents.Lease
  alias Tuist.Repo
  alias Tuist.Threads
  alias Tuist.Threads.Approval
  alias Tuist.Threads.Run
  alias Tuist.Threads.Shipping

  @run_ms 900_000

  @impl true
  def perform(%Oban.Job{args: %{"run_id" => id}}) do
    case Repo.get(Run, id) do
      %Run{kind: "ship"} -> perform_ship(id)
      # An inference job an earlier release enqueued: its thread's session
      # hosts the run now, at an epoch later than the job's attempts.
      %Run{status: status} = run when status in ["queued", "running"] -> hand_to_session(run)
      _ -> :ok
    end
  end

  defp perform_ship(id) do
    case Threads.claim(id) do
      {:ok, {run, thread}} -> execute(run, thread)
      {:error, :stale_run} -> :ok
      {:error, :forbidden} -> :ok
    end
  end

  defp hand_to_session(run) do
    id = to_string(run.thread_id)
    Lease.want(id, "thread", min_epoch: run.attempt)
    Lease.wake(id)
    :ok
  end

  defp execute(run, thread) do
    Process.flag(:trap_exit, true)
    parent = self()

    now = System.monotonic_time(:millisecond)
    deadline = now + @run_ms

    task =
      Task.Supervisor.async_nolink(Tuist.Threads.Tasks, fn ->
        Process.link(parent)
        Shipping.execute(thread, Repo.get!(Approval, run.approval_id), run)
      end)

    try do
      await(task, run, deadline, now + 5_000)
    after
      Task.shutdown(task, :brutal_kill)
    end
  end

  defp await(task, run, deadline, heartbeat_at) do
    now = System.monotonic_time(:millisecond)

    if now >= heartbeat_at do
      if now < deadline and Threads.heartbeat(run) == :ok and Threads.owns_run?(run.id, run.attempt) do
        await(task, run, deadline, System.monotonic_time(:millisecond) + 5_000)
      else
        :ok
      end
    else
      receive do
        {ref, result} when ref == task.ref ->
          Process.demonitor(task.ref, [:flush])
          Threads.finish(run, result)
          :ok

        {:DOWN, ref, :process, _pid, _reason} when ref == task.ref ->
          :ok

        {:EXIT, _pid, :normal} ->
          await(task, run, deadline, heartbeat_at)

        {:EXIT, _pid, _reason} ->
          :ok
      after
        heartbeat_at - now -> await(task, run, deadline, heartbeat_at)
      end
    end
  end
end
