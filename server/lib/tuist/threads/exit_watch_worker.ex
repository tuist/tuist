defmodule Tuist.Threads.ExitWatchWorker do
  @moduledoc """
  Delivers a command's end to the Condukt session that parked on it, as
  `Tuist.Threads.Sandbox.watch_process/3` asked: waits on the command with
  `Commands.wait/3`, then calls `Condukt.signal/4` with the session id. As an
  Oban job it survives the node that parked the call, so a deploy does not
  lose the wake. The session's own watcher may deliver first; the second
  delivery finds the key used and changes nothing.

  A sandbox that stopped running is not resumed to look: the command's row
  is the answer once `CommandWatchWorker` records it.

  One job follows a command. A call that parks on it again, under a new key,
  replaces the key of the job already following it, which reads its key back
  just before delivering, so a delivery started under the old key uses the
  new one. Each job holds a slot for its long-poll, so the jobs have their own
  queue rather than taking `:threads` slots from runs.
  """
  use Oban.Worker,
    queue: :thread_exit_watches,
    max_attempts: 5,
    unique: [keys: [:command_id], states: [:available, :scheduled, :executing, :retryable], period: :infinity],
    replace: [available: [:args], scheduled: [:args], executing: [:args], retryable: [:args]]

  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Commands
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.SandboxCommand
  alias Tuist.Threads.Sandbox, as: ThreadSandbox

  @wait_seconds 25
  @retry_seconds 15

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: args}) do
    %{"sandbox_id" => sandbox_id, "account_id" => account_id, "command_id" => id} = args

    with {:ok, signal} <- signal(args["signal"]),
         %Sandbox{account_id: ^account_id} = sandbox <- Sandboxes.get_sandbox_by_id(sandbox_id),
         %SandboxCommand{} = command <- Repo.get_by(SandboxCommand, id: id, sandbox_id: sandbox_id) do
      watch(sandbox, command, fn status -> deliver(job_id, args, signal, status) end)
    else
      _ -> :ok
    end
  end

  defp watch(_sandbox, %SandboxCommand{status: status} = command, deliver) when status != :running,
    do: deliver.(ThreadSandbox.status(%{status: Atom.to_string(status), exit_code: command.exit_code}))

  defp watch(%Sandbox{state: :running} = sandbox, command, deliver) do
    case Commands.wait(sandbox, command.id, @wait_seconds) do
      {:ok, %{status: "running"}} -> {:snooze, 1}
      {:ok, read} -> deliver.(ThreadSandbox.status(read))
      {:error, :not_found} -> deliver.({:error, :not_found})
      {:error, _reason} -> {:snooze, @retry_seconds}
    end
  end

  defp watch(_sandbox, _command, _deliver), do: {:snooze, @retry_seconds}

  # The stored args, which a later park may have replaced while this ran.
  defp deliver(job_id, args, signal, status) do
    args =
      case job_id && Repo.get(Oban.Job, job_id) do
        %Oban.Job{args: current} -> current
        _not_stored -> args
      end

    _ = Condukt.signal(args["session_id"], signal, args["key"], status)
    :ok
  end

  # Only a loaded `Condukt.Signal` module, named by the server when it queued
  # the job.
  defp signal(name) when is_binary(name) do
    module = String.to_existing_atom(name)
    if Code.ensure_loaded?(module) and function_exported?(module, :cast, 1), do: {:ok, module}, else: :error
  rescue
    ArgumentError -> :error
  end

  defp signal(_name), do: :error
end
